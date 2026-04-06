defmodule BenchArena.Adapters.AgentLoopAdapter do
  @moduledoc """
  Adapter that runs questions through the Elan agent loop in-process.
  Falls back to {:error, :elan_unavailable} if the Elan dependency is not loaded.
  """

  @behaviour BenchArena.Adapter

  alias BenchArena.Corpus.Question

  @impl true
  @spec execute(Question.t()) ::
          {:ok, %{answer: String.t(), tokens_in: integer(), tokens_out: integer()}}
          | {:error, term()}
  def execute(%Question{} = question) do
    if elan_available?() do
      run_with_elan(question)
    else
      {:error, :elan_unavailable}
    end
  end

  defp elan_available? do
    Code.ensure_loaded?(Elan.AgentLoop) and Code.ensure_loaded?(Elan.AgentProcess) and
      Code.ensure_loaded?(Elan.LLMAdapter)
  end

  defp run_with_elan(question) do
    start = System.monotonic_time(:millisecond)

    try do
      # Configure Elan to use Perplexity
      Elan.LLMAdapter.set_provider("perplexity")
      Elan.LLMAdapter.set_model("sonar")

      agent_id = "bench_#{:erlang.unique_integer([:positive])}"
      task_id = "bench_task_#{agent_id}"

      # Initialize agent
      Elan.AgentProcess.init_agent(agent_id)

      # Assign task
      Elan.AgentProcess.assign_task(agent_id, task_id)

      # Add the user message to conversation
      Elan.AgentProcess.append_conversation_turn(agent_id, %{
        role: "user",
        content: question.prompt
      })

      # Run the agent loop
      result =
        Elan.AgentLoop.run(agent_id, task_id, %{
          max_turns: 3,
          timeout_ms: 25_000,
          messages: [%{role: "user", content: question.prompt}]
        })

      _elapsed = System.monotonic_time(:millisecond) - start

      case result do
        {:ok, %{final_text: text}} when is_binary(text) ->
          {:ok,
           %{
             answer: text,
             tokens_in: estimate_tokens(question.prompt),
             tokens_out: estimate_tokens(text)
           }}

        {:ok, %{} = map} ->
          answer =
            Map.get(map, :final_text) || Map.get(map, :response) || Map.get(map, :final_answer) ||
              inspect(map)

          {:ok,
           %{
             answer: to_string(answer),
             tokens_in: estimate_tokens(question.prompt),
             tokens_out: estimate_tokens(to_string(answer))
           }}

        {:error, reason} ->
          {:error, {:elan_loop_error, reason}}
      end
    rescue
      e ->
        {:error, {:elan_exception, Exception.message(e)}}
    catch
      :exit, reason ->
        {:error, {:elan_exit, reason}}
    end
  end

  defp estimate_tokens(text) when is_binary(text), do: max(div(String.length(text), 4), 1)
  defp estimate_tokens(_), do: 1
end
