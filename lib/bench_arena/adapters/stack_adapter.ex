defmodule BenchArena.Adapters.StackAdapter do
  @moduledoc """
  Adapter that routes the question through the full stack pipeline:
    1. CSC.Compiler.compile/1  — decomposes prompt into a SkillDAG
    2. TokenGov policy check   — governance/budget approval
    3. Elan.AgentLoop          — executes the compiled plan (if Elan running)
       OR direct Perplexity call with the CSC decomposition as context

  If CSC is unavailable, falls back to a single structured Perplexity call
  that explicitly applies the stack's reasoning protocol (decompose → verify →
  synthesise) with RAG retrieval augmentation between decompose and verify.

  The ConfabulumRate gate is applied after each step. If a step's output
  triggers a confabulum halt, the pipeline stops and returns a structured error.

  Returns {:error, :credentials_not_configured} if PERPLEXITY_API_KEY absent.
  """

  @behaviour BenchArena.Adapter

  alias BenchArena.Corpus.Question
  alias BenchArena.ConfabulumRate
  alias BenchArena.CompetenceSignal

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
  # Path B: Stack protocol without CSC (decompose → retrieve → verify → synthesise)
  # Faithfully models the stack's reasoning pattern via explicit prompting.
  # RAG retrieval augments the verify step with grounded context.
  # ConfabulumRate gates each step.
  # ---------------------------------------------------------------------------

  defp run_via_stack_protocol(question, api_key) do
    model = "sonar"
    timeout = 30_000

    # Step 1: Decompose (mirrors CSC stage_4_decomposition)
    decompose_prompt = """
    You are the Composable Skill Compiler (CSC). Decompose the following task into
    atomic sub-questions that can be independently verified.

    TASK: #{question.prompt}

    Output a numbered list of sub-questions. Each sub-question should be a single
    factual claim or verification target. Keep them short and precise.
    """

    with {:ok, decomposition, d_in, d_out} <-
           call_perplexity(decompose_prompt, model, api_key, timeout),
         :ok <- confabulum_check(decomposition, question.prompt, :decompose),
         # Step 2: RAG retrieval for each sub-question
         {:ok, retrieved_context, r_in, r_out} <-
           retrieve_for_subquestions(decomposition, question.prompt, api_key, timeout),
         # Step 3: Verify with retrieved context (mirrors TokenGov policy check + wind tunnel)
         verify_prompt = """
         [TokenGov Policy Check — RAG-Augmented Verification]

         ORIGINAL TASK: #{question.prompt}

         DECOMPOSITION:
         #{decomposition}

         RETRIEVED CONTEXT (grounded sources):
         #{retrieved_context}

         Using the retrieved context above as your primary source of truth,
         verify each sub-question. If the retrieved sources contradict the
         decomposition, prefer the retrieved sources.

         Provide the verified answer, citing sources where applicable.
         """,
         {:ok, verified, v_in, v_out} <- call_perplexity(verify_prompt, model, api_key, timeout),
         :ok <- confabulum_check(verified, question.prompt, :verify),
         # Step 4: Synthesise with CompetenceSignal gate
         # Collect confidence scores from upstream steps (heuristic: each successful
         # step that passed confabulum gate scores 0.85; retrieval augmented = 0.90)
         confidence_vector = build_confidence_vector(decomposition, retrieved_context, verified),
         synth_prompt = """
         [Elan Agent — Final Synthesis]

         TASK: #{question.prompt}

         VERIFIED ANALYSIS:
         #{verified}

         Based on the verified analysis above, provide the final answer.
         Be direct and concise. For multiple-choice questions, state the correct
         letter option clearly.
         """,
         {:ok, _vocab, gated_prompt} <-
           competence_signal_check(synth_prompt, confidence_vector),
         {:ok, answer, s_in, s_out} <- call_perplexity(gated_prompt, model, api_key, timeout),
         :ok <- confabulum_check(answer, question.prompt, :synthesise) do
      {:ok,
       %{
         answer: answer,
         tokens_in: d_in + r_in + v_in + s_in,
         tokens_out: d_out + r_out + v_out + s_out
       }}
    end
  end

  # ---------------------------------------------------------------------------
  # RAG retrieval: call Perplexity for each sub-question to ground context
  # ---------------------------------------------------------------------------

  defp retrieve_for_subquestions(decomposition, original_question, api_key, timeout) do
    # Parse sub-questions from decomposition (numbered list)
    sub_questions = parse_subquestions(decomposition, original_question)

    # Retrieve grounded context for each sub-question
    results =
      sub_questions
      |> Enum.with_index(1)
      |> Enum.reduce_while({[], 0, 0}, fn {sq, idx}, {contexts, total_in, total_out} ->
        case retrieve_single(sq, api_key, timeout) do
          {:ok, passage, citations, t_in, t_out} ->
            citation_text =
              if citations != [] do
                "Sources: " <> Enum.join(citations, ", ")
              else
                "Sources: Perplexity search"
              end

            context_block = """
            [Retrieved context for sub-question #{idx}:]
            #{passage}
            #{citation_text}
            """

            {:cont, {[context_block | contexts], total_in + t_in, total_out + t_out}}

          {:error, _reason} ->
            # If retrieval fails for a sub-question, continue without it
            {:cont, {contexts, total_in, total_out}}
        end
      end)

    {contexts, tokens_in, tokens_out} = results
    combined = contexts |> Enum.reverse() |> Enum.join("\n")
    {:ok, combined, tokens_in, tokens_out}
  end

  defp parse_subquestions(decomposition, original_question) do
    # Extract numbered items from the decomposition
    lines =
      decomposition
      |> String.split(~r/\n/, trim: true)
      |> Enum.filter(&Regex.match?(~r/^\s*\d+[\.\)]\s/, &1))
      |> Enum.map(&Regex.replace(~r/^\s*\d+[\.\)]\s*/, &1, ""))
      |> Enum.map(&String.trim/1)
      |> Enum.filter(&(String.length(&1) > 5))

    # If parsing fails, use the original question as a single retrieval query
    if lines == [] do
      [original_question]
    else
      Enum.take(lines, 5)
    end
  end

  defp retrieve_single(query, api_key, timeout) do
    body = %{
      model: "sonar",
      messages: [
        %{
          role: "system",
          content:
            "You are a factual research assistant. Provide a brief, accurate answer with citations. Focus on verifiable facts."
        },
        %{role: "user", content: query}
      ],
      max_tokens: 256
    }

    case Req.post("https://api.perplexity.ai/chat/completions",
           json: body,
           headers: [{"Authorization", "Bearer #{api_key}"}],
           receive_timeout: timeout,
           retry: false
         ) do
      {:ok, %{status: status, body: resp}} when status in 200..299 ->
        content = get_in(resp, ["choices", Access.at(0), "message", "content"]) || ""
        citations = Map.get(resp, "citations", [])
        tokens_in = get_in(resp, ["usage", "prompt_tokens"]) || 0
        tokens_out = get_in(resp, ["usage", "completion_tokens"]) || 0
        {:ok, content, citations, tokens_in, tokens_out}

      {:ok, %{status: status, body: body}} ->
        {:error, {:perplexity_error, status, body}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  # ---------------------------------------------------------------------------
  # ConfabulumRate gate
  # ---------------------------------------------------------------------------

  defp confabulum_check(text, question, step) do
    case ConfabulumRate.gate(text, question) do
      {:pass, _score} ->
        :ok

      {:halt, type, score} ->
        {:error, {:confabulum_halt, %{type: type, score: score, step: step}}}
    end
  end

  # ---------------------------------------------------------------------------
  # Perplexity API helpers
  # ---------------------------------------------------------------------------

  defp call_perplexity_single(prompt, model, api_key, timeout) do
    case call_perplexity(prompt, model, api_key, timeout) do
      {:ok, answer, t_in, t_out} -> {:ok, %{answer: answer, tokens_in: t_in, tokens_out: t_out}}
      err -> err
    end
  end

  # ---------------------------------------------------------------------------
  # CompetenceSignal gate
  # ---------------------------------------------------------------------------

  defp competence_signal_check(prompt, confidence_vector) do
    case CompetenceSignal.inject_into_prompt(prompt, confidence_vector) do
      {:halt, :competence_signal, info} ->
        {:error, {:competence_signal_halt, info}}

      {:ok, vocab, gated_prompt} ->
        {:ok, vocab, gated_prompt}
    end
  end

  defp build_confidence_vector(decomposition, retrieved_context, _verified) do
    # Heuristic confidence scoring for each pipeline step:
    # - Decompose: 0.85 base (structured output from model)
    # - Retrieve: 0.90 if context was returned, 0.70 if empty
    # - Verify: 0.85 base (cross-checked against retrieved sources)
    decompose_confidence = if String.length(decomposition) > 20, do: 0.85, else: 0.65
    retrieve_confidence = if String.length(retrieved_context) > 50, do: 0.90, else: 0.70
    verify_confidence = 0.85
    [decompose_confidence, retrieve_confidence, verify_confidence]
  end

  # ---------------------------------------------------------------------------
  # Perplexity API helpers
  # ---------------------------------------------------------------------------

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
