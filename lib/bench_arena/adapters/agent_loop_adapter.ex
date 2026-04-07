defmodule BenchArena.Adapters.AgentLoopAdapter do
  @moduledoc """
  Adapter that runs the question through the Elan agent loop in-process.

  Requires :elan as a dependency and PERPLEXITY_API_KEY set.
  If Elan's Registry/AgentProcess supervisor is not running (e.g. bare mix run),
  falls back to a direct multi-turn Perplexity API call that simulates agent-loop
  behaviour: plan → execute → reflect (3 turns, sonar model).

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
      run_agent_loop(question, api_key)
    end
  end

  # ---------------------------------------------------------------------------
  # Try Elan in-process first; fall back to direct multi-turn Perplexity call
  # ---------------------------------------------------------------------------

  defp run_agent_loop(question, api_key) do
    if elan_available?() do
      run_via_elan(question, api_key)
    else
      run_via_perplexity_multiturn(question, api_key)
    end
  end

  defp elan_available? do
    Code.ensure_loaded?(Elan.AgentProcess) and
      Code.ensure_loaded?(Elan.AgentLoop) and
      Process.whereis(Elan.Registry) != nil
  end

  # ---------------------------------------------------------------------------
  # Path A: Elan in-process (requires Elan.Application supervision tree running)
  # ---------------------------------------------------------------------------

  defp run_via_elan(question, _api_key) do
    agent_id = "bench_#{:erlang.unique_integer([:positive])}"

    try do
      Elan.AgentProcess.init_agent(agent_id)

      result =
        Elan.AgentLoop.run(agent_id, "bench_task_#{agent_id}", %{
          max_turns: 3,
          timeout_ms: 25_000,
          messages: [%{role: "user", content: question.prompt}]
        })

      extract_elan_result(result)
    catch
      kind, reason ->
        {:error, {:elan_exit, {kind, reason}}}
    end
  end

  defp extract_elan_result({:ok, %{final_answer: answer} = r}) when is_binary(answer) do
    {:ok,
     %{
       answer: answer,
       tokens_in: get_in(r, [:usage, :tokens_in]) || 0,
       tokens_out: get_in(r, [:usage, :tokens_out]) || 0
     }}
  end

  defp extract_elan_result({:ok, %{response: answer}}) when is_binary(answer) do
    {:ok, %{answer: answer, tokens_in: 0, tokens_out: 0}}
  end

  defp extract_elan_result({:ok, result}) do
    {:ok, %{answer: inspect(result), tokens_in: 0, tokens_out: 0}}
  end

  defp extract_elan_result({:error, _} = err), do: err

  # ---------------------------------------------------------------------------
  # Path B: Direct multi-turn Perplexity call (plan → execute → reflect)
  # This faithfully simulates a 3-step agent loop without the Elan supervisor.
  # ---------------------------------------------------------------------------

  defp run_via_perplexity_multiturn(question, api_key) do
    model = "sonar"
    timeout = 30_000

    # Turn 1: plan
    plan_prompt = """
    You are an agent that solves tasks in structured steps.
    TASK: #{question.prompt}

    Step 1 — PLAN: Briefly outline your approach (2-3 sentences).
    """

    with {:ok, plan, t1_in, t1_out} <- call_perplexity(plan_prompt, model, api_key, timeout),
         # Turn 2: execute
         exec_prompt = "#{plan_prompt}\n\nPLAN: #{plan}\n\nStep 2 — EXECUTE: Solve the task fully.",
         {:ok, execution, t2_in, t2_out} <-
           call_perplexity(exec_prompt, model, api_key, timeout),
         # Turn 3: reflect + final answer
         reflect_prompt =
           "#{exec_prompt}\n\nEXECUTION: #{execution}\n\nStep 3 — REFLECT: Is the answer correct? State your FINAL ANSWER clearly.",
         {:ok, final, t3_in, t3_out} <-
           call_perplexity(reflect_prompt, model, api_key, timeout) do
      {:ok,
       %{
         answer: final,
         tokens_in: t1_in + t2_in + t3_in,
         tokens_out: t1_out + t2_out + t3_out
       }}
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
