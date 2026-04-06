defmodule BenchArena.Adapters.PerplexityStandardAdapter do
  @moduledoc """
  Adapter that calls the Perplexity API in standard (non-reasoning) mode.
  Uses the `sonar` model for fast, direct answers.
  """

  @behaviour BenchArena.Adapter

  alias BenchArena.Corpus.Question

  @api_url "https://api.perplexity.ai/chat/completions"

  @impl true
  @spec execute(Question.t()) ::
          {:ok, %{answer: String.t(), tokens_in: integer(), tokens_out: integer()}}
          | {:error, term()}
  def execute(%Question{} = question) do
    case get_api_key() do
      nil ->
        {:error, :credentials_not_configured}

      api_key ->
        call_api(api_key, question)
    end
  end

  defp get_api_key do
    Application.get_env(:bench_arena, :perplexity_api_key) ||
      System.get_env("PERPLEXITY_API_KEY")
  end

  defp call_api(api_key, question) do
    body = %{
      model: "sonar",
      messages: [%{role: "user", content: question.prompt}],
      max_tokens: 1024,
      stream: false
    }

    case Req.post(@api_url,
           json: body,
           headers: [{"authorization", "Bearer #{api_key}"}],
           receive_timeout: 30_000,
           retry: false
         ) do
      {:ok, %{status: status, body: resp_body}} when status in 200..299 ->
        answer = get_in(resp_body, ["choices", Access.at(0), "message", "content"]) || ""
        tokens_in = get_in(resp_body, ["usage", "prompt_tokens"]) || 0
        tokens_out = get_in(resp_body, ["usage", "completion_tokens"]) || 0

        {:ok, %{answer: answer, tokens_in: tokens_in, tokens_out: tokens_out}}

      {:ok, %{status: status, body: resp_body}} ->
        {:error, {:api_error, status, resp_body}}

      {:error, %{reason: reason}} ->
        {:error, {:request_failed, reason}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end
end
