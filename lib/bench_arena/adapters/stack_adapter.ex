defmodule BenchArena.Adapters.StackAdapter do
  @moduledoc """
  Adapter that calls the stack via CSC compile and TokenGov policy check.
  Routes through the full mediated execution pipeline.
  """

  @behaviour BenchArena.Adapter

  alias BenchArena.Corpus.Question

  @impl true
  @spec execute(Question.t()) ::
          {:ok, %{answer: String.t(), tokens_in: integer(), tokens_out: integer()}}
          | {:error, term()}
  def execute(%Question{} = question) do
    csc_url = Application.get_env(:bench_arena, :stack_csc_url, "http://localhost:4003")
    token_gov_url = Application.get_env(:bench_arena, :stack_token_gov_url, "http://localhost:4002")
    timeout = Application.get_env(:bench_arena, :adapter_timeout_ms, 30_000)

    with {:ok, compiled} <- csc_compile(csc_url, question, timeout),
         {:ok, _policy} <- token_gov_check(token_gov_url, question, timeout) do
      {:ok,
       %{
         answer: compiled["result"] || compiled["answer"] || inspect(compiled),
         tokens_in: compiled["tokens_in"] || get_in(compiled, ["usage", "tokens_in"]) || 0,
         tokens_out: compiled["tokens_out"] || get_in(compiled, ["usage", "tokens_out"]) || 0
       }}
    end
  end

  defp req_opts(extra) do
    if Application.get_env(:bench_arena, :adapter_retry, true) do
      extra
    else
      Keyword.put(extra, :retry, false)
    end
  end

  defp csc_compile(csc_url, question, timeout) do
    body = %{
      input: question.prompt,
      context: %{tier: question.tier, question_id: question.id}
    }

    case Req.post("#{csc_url}/compile", req_opts(json: body, receive_timeout: timeout)) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        {:error, {:csc_error, status, body}}

      {:error, %{reason: reason}} ->
        {:error, {:csc_unavailable, reason}}

      {:error, reason} ->
        {:error, {:csc_unavailable, reason}}
    end
  end

  defp token_gov_check(token_gov_url, question, timeout) do
    body = %{
      action: "benchmark_execution",
      context: %{tier: question.tier, question_id: question.id, prompt_length: String.length(question.prompt)}
    }

    case Req.post("#{token_gov_url}/governance/proposals", req_opts(json: body, receive_timeout: timeout)) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        {:error, {:token_gov_error, status, body}}

      {:error, %{reason: reason}} ->
        {:error, {:token_gov_unavailable, reason}}

      {:error, reason} ->
        {:error, {:token_gov_unavailable, reason}}
    end
  end
end
