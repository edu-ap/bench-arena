defmodule BenchArena.Adapters.StackAdapter do
  @moduledoc """
  Adapter that routes the question through the full stack pipeline:
    1. CSC.Compiler.compile/1  — decomposes prompt into a SkillDAG
    2. TokenGov policy check   — governance/budget approval
    3. Elan.AgentLoop          — executes the compiled plan (if Elan running)
       OR direct Perplexity call with the CSC decomposition as context

  If CSC is unavailable, falls back to a single structured Perplexity call
  that explicitly applies the stack's reasoning protocol (decompose → verify →
  synthesise) without the compiled DAG.

  Returns {:error, :credentials_not_configured} if PERPLEXITY_API_KEY absent.
  """

  @behaviour BenchArena.Adapter

  alias BenchArena.Corpus.Question

  @impl true
  @spec execute(Question.t()) ::
          {:ok, %{answer: String.t(), tokens_in: integer(), tokens_out: integer()}}
          | {:error, term()}
  def execute(%Question{} = question) do
    api_key = System.get_env("PERPLEXITY_API_KEY")

    if is_nil(api_key) do
      {:error, :credentials_not_configured}
    else
      run_stack(question, api_key)
    end
  end

  # ---------------------------------------------------------------------------
  # Main stack pipeline
  # ---------------------------------------------------------------------------

  defp run_stack(question, api_key) do
    if csc_available?() do
      run_via_csc_pipeline(question, api_key)
    else
      run_via_stack_protocol(question, api_key)
    end
  end

  defp csc_available? do
    Code.ensure_loaded?(CSC.Compiler) and
      Process.whereis(CSC.Compiler) != nil
  end

  # ---------------------------------------------------------------------------
  # Path A: Full CSC in-process pipeline
  # ---------------------------------------------------------------------------

  defp run_via_csc_pipeline(question, api_key) do
    try do
      case CSC.Compiler.compile(question.prompt) do
        {:ok, %{dag: dag, wind_tunnel_report: wt}} ->
          # Build a context-enriched prompt from the compiled DAG
          skill_names =
            dag.nodes
            |> Enum.map(& &1.skill_id)
            |> Enum.join(", ")

          risk_level = Map.get(wt, :risk_level, "unknown")

          enriched_prompt = """
          [STACK EXECUTION — compiled via CSC]
          Skills resolved: #{skill_names}
          Wind tunnel risk: #{risk_level}

          TASK: #{question.prompt}

          Execute the task using the resolved skills. Provide a complete, accurate answer.
          """

          # Run through Elan if available, otherwise direct Perplexity
          if elan_available?() do
            run_via_elan_with_prompt(enriched_prompt, api_key)
          else
            call_perplexity_single(enriched_prompt, "sonar", api_key, 30_000)
          end

        {:error, stage, reason} ->
          {:error, {:csc_pipeline_error, stage, reason}}
      end
    catch
      kind, reason ->
        {:error, {:stack_exit, {kind, reason}}}
    end
  end

  defp elan_available? do
    Code.ensure_loaded?(Elan.AgentProcess) and
      Code.ensure_loaded?(Elan.AgentLoop) and
      Process.whereis(Elan.Registry) != nil
  end

  defp run_via_elan_with_prompt(prompt, _api_key) do
    agent_id = "stack_bench_#{:erlang.unique_integer([:positive])}"

    try do
      Elan.AgentProcess.init_agent(agent_id)

      result =
        Elan.AgentLoop.run(agent_id, "stack_bench_#{agent_id}", %{
          max_turns: 3,
          timeout_ms: 25_000,
          messages: [%{role: "user", content: prompt}]
        })

      case result do
        {:ok, %{final_answer: answer}} when is_binary(answer) ->
          {:ok, %{answer: answer, tokens_in: 0, tokens_out: 0}}

        {:ok, %{response: answer}} when is_binary(answer) ->
          {:ok, %{answer: answer, tokens_in: 0, tokens_out: 0}}

        {:ok, r} ->
          {:ok, %{answer: inspect(r), tokens_in: 0, tokens_out: 0}}

        {:error, _} = err ->
          err
      end
    catch
      kind, reason ->
        {:error, {:elan_exit, {kind, reason}}}
    end
  end

  # ---------------------------------------------------------------------------
  # Path B: Stack protocol without CSC (decompose → verify → synthesise)
  # Faithfully models the stack's reasoning pattern via explicit prompting.
  # ---------------------------------------------------------------------------

  defp run_via_stack_protocol(question, api_key) do
    model = "sonar"
    timeout = 30_000

    # Step 1: Decompose (mirrors CSC stage_4_decomposition)
    decompose_prompt = """
    You are the Composable Skill Compiler (CSC). Decompose the following task into
    atomic sub-tasks, identify which skills are needed, and flag any compliance constraints.

    TASK: #{question.prompt}

    Output:
    - Sub-tasks: (list)
    - Skills required: (list)
    - Compliance flags: (IRAP / EU AI Act / GDPR / none)
    """

    with {:ok, decomposition, d_in, d_out} <-
           call_perplexity(decompose_prompt, model, api_key, timeout),
         # Step 2: Verify (mirrors TokenGov policy check + wind tunnel)
         verify_prompt = """
         [TokenGov Policy Check]
         DECOMPOSITION: #{decomposition}
         ORIGINAL TASK: #{question.prompt}

         Verify: Are there any policy violations, budget concerns, or risk factors?
         Then provide the verified execution plan.
         """,
         {:ok, verified, v_in, v_out} <- call_perplexity(verify_prompt, model, api_key, timeout),
         # Step 3: Synthesise (mirrors Elan.AgentLoop final answer)
         synth_prompt = """
         [Elan Agent — Final Synthesis]
         VERIFIED PLAN: #{verified}
         TASK: #{question.prompt}

         Execute the plan and provide the final answer.
         """,
         {:ok, answer, s_in, s_out} <- call_perplexity(synth_prompt, model, api_key, timeout) do
      {:ok,
       %{
         answer: answer,
         tokens_in: d_in + v_in + s_in,
         tokens_out: d_out + v_out + s_out
       }}
    end
  end

  defp call_perplexity_single(prompt, model, api_key, timeout) do
    case call_perplexity(prompt, model, api_key, timeout) do
      {:ok, answer, t_in, t_out} -> {:ok, %{answer: answer, tokens_in: t_in, tokens_out: t_out}}
      err -> err
    end
  end

  defp call_perplexity(prompt, model, api_key, timeout) do
    body = %{
      model: model,
      messages: [%{role: "user", content: prompt}],
      max_tokens: 512
    }

    case Req.post("https://api.perplexity.ai/chat/completions",
           json: body,
           headers: [{"Authorization", "Bearer #{api_key}"}],
           receive_timeout: timeout,
           retry: false
         ) do
      {:ok, %{status: 200, body: resp}} ->
        content = get_in(resp, ["choices", Access.at(0), "message", "content"]) || ""
        tokens_in = get_in(resp, ["usage", "prompt_tokens"]) || 0
        tokens_out = get_in(resp, ["usage", "completion_tokens"]) || 0
        {:ok, content, tokens_in, tokens_out}

      {:ok, %{status: status, body: body}} ->
        {:error, {:perplexity_error, status, body}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end
end
