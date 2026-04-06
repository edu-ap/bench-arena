defmodule BenchArena.Adapters.AgentLoopAdapter do
  @moduledoc """
  Adapter that calls the Elan HTTP API agent loop.
  POSTs to /run_skill with skill_id "agent_loop".
  """

  @behaviour BenchArena.Adapter

  alias BenchArena.Corpus.Question

  @impl true
  @spec execute(Question.t()) ::
          {:ok, %{answer: String.t(), tokens_in: integer(), tokens_out: integer()}}
          | {:error, term()}
  def execute(%Question{} = question) do
    base_url = Application.get_env(:bench_arena, :agent_loop_url, "http://localhost:4001")
    timeout = Application.get_env(:bench_arena, :adapter_timeout_ms, 30_000)

    case health_check(base_url, timeout) do
      :ok ->
        run_skill(base_url, question, timeout)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp health_check(base_url, timeout) do
    case Req.get("#{base_url}/health", receive_timeout: timeout) do
      {:ok, %{status: status}} when status in 200..299 ->
        :ok

      {:ok, %{status: status}} ->
        {:error, {:health_check_failed, status}}

      {:error, %{reason: reason}} ->
        {:error, {:elan_unavailable, reason}}

      {:error, reason} ->
        {:error, {:elan_unavailable, reason}}
    end
  end

  defp run_skill(base_url, question, timeout) do
    body = %{
      skill_id: "agent_loop",
      input: question.prompt
    }

    case Req.post("#{base_url}/run_skill",
           json: body,
           receive_timeout: timeout
         ) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok,
         %{
           answer: get_in(body, ["result"]) || get_in(body, ["answer"]) || inspect(body),
           tokens_in: get_in(body, ["usage", "tokens_in"]) || get_in(body, ["tokens_in"]) || 0,
           tokens_out: get_in(body, ["usage", "tokens_out"]) || get_in(body, ["tokens_out"]) || 0
         }}

      {:ok, %{status: status, body: body}} ->
        {:error, {:api_error, status, body}}

      {:error, %{reason: reason}} ->
        {:error, {:request_failed, reason}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end
end
