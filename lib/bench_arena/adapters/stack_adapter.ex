defmodule BenchArena.Adapters.StackAdapter do
  @moduledoc """
  Adapter that routes through the full mediated execution pipeline:
  CSC compile → TokenGov policy check → Elan execution.
  Falls back to {:error, :stack_unavailable} if dependencies are not loaded.
  """

  @behaviour BenchArena.Adapter

  alias BenchArena.Corpus.Question

  @impl true
  @spec execute(Question.t()) ::
          {:ok, %{answer: String.t(), tokens_in: integer(), tokens_out: integer()}}
          | {:error, term()}
  def execute(%Question{} = question) do
    csc_available = Code.ensure_loaded?(CSC.Compiler)

    if not csc_available do
      {:error, :stack_unavailable}
    else
      run_stack_pipeline(question)
    end
  end

  defp run_stack_pipeline(question) do
    start = System.monotonic_time(:millisecond)

    try do
      case CSC.Compiler.compile(question.prompt) do
        {:ok, result} ->
          # TokenGov policy check (non-blocking — just for observability)
          _policy = try_token_gov_check(question)

          # Extract answer from the compilation result
          answer = extract_csc_answer(result, question)
          _elapsed = System.monotonic_time(:millisecond) - start

          {:ok,
           %{
             answer: answer,
             tokens_in: estimate_tokens(question.prompt),
             tokens_out: estimate_tokens(answer)
           }}

        {:error, stage, reason} ->
          {:error, {:csc_pipeline_error, stage, reason}}

        {:error, reason} ->
          {:error, {:csc_error, reason}}
      end
    rescue
      e ->
        {:error, {:stack_exception, Exception.message(e)}}
    catch
      :exit, reason ->
        {:error, {:stack_exit, reason}}
    end
  end

  defp try_token_gov_check(question) do
    if Code.ensure_loaded?(TokenGov.BudgetController) do
      try do
        TokenGov.BudgetController.check_budget("bench_arena", estimate_tokens(question.prompt))
      rescue
        _ -> :policy_check_skipped
      end
    else
      :token_gov_unavailable
    end
  end

  defp extract_csc_answer(result, question) do
    # CSC produces a CompilationResult with a DAG. Try to extract meaningful text.
    cond do
      is_map(result) and Map.has_key?(result, :canonical_ir) ->
        ir = Map.get(result, :canonical_ir)
        wind_tunnel = Map.get(result, :wind_tunnel_report, %{})
        risk = Map.get(wind_tunnel, :risk_score, "n/a")
        "#{inspect(ir)} [wind_tunnel_risk=#{risk}]"

      is_map(result) and Map.has_key?(result, :dag) ->
        dag = Map.get(result, :dag)
        # Try to run the DAG through Elan if available
        maybe_run_dag_through_elan(dag, question)

      is_binary(result) ->
        result

      true ->
        inspect(result)
    end
  end

  defp maybe_run_dag_through_elan(dag, question) do
    if Code.ensure_loaded?(Elan.AgentLoop) and Code.ensure_loaded?(Elan.AgentProcess) do
      try do
        Elan.LLMAdapter.set_provider("perplexity")
        Elan.LLMAdapter.set_model("sonar")

        agent_id = "stack_bench_#{:erlang.unique_integer([:positive])}"
        task_id = "stack_task_#{agent_id}"
        Elan.AgentProcess.init_agent(agent_id)
        Elan.AgentProcess.assign_task(agent_id, task_id)

        prompt = "Based on this compiled skill plan: #{inspect(dag)}\nAnswer this question: #{question.prompt}"

        Elan.AgentProcess.append_conversation_turn(agent_id, %{
          role: "user",
          content: prompt
        })

        case Elan.AgentLoop.run(agent_id, task_id, %{
               max_turns: 3,
               timeout_ms: 25_000,
               messages: [%{role: "user", content: prompt}]
             }) do
          {:ok, %{final_text: text}} when is_binary(text) -> text
          {:ok, map} -> Map.get(map, :final_text, inspect(map))
          _ -> inspect(dag)
        end
      rescue
        _ -> inspect(dag)
      end
    else
      inspect(dag)
    end
  end

  defp estimate_tokens(text) when is_binary(text), do: max(div(String.length(text), 4), 1)
  defp estimate_tokens(_), do: 1
end
