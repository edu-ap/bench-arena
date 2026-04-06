defmodule BenchArena.Adapters.BaselineAdapter do
  @moduledoc """
  Baseline adapter: single direct LLM query to Perplexity sonar model.
  No routing, no tool calls, no orchestration. Used as a floor comparison.

  Requires PERPLEXITY_API_KEY env var. Falls back to {:error, :credentials_not_configured}
  if the key is absent.
  """

  @behaviour BenchArena.Adapter

  alias BenchArena.Corpus.Question

  @impl true
  @spec execute(Question.t()) ::
          {:ok, %{answer: String.t(), tokens_in: integer(), tokens_out: integer()}}
          | {:error, term()}
  def execute(%Question{} = question) do
    api_key = System.get_env("PERPLEXITY_API_KEY") || Application.get_env(:bench_arena, :perplexity_api_key)

    if is_nil(api_key) or api_key == "" do
      {:error, :credentials_not_configured}
    else
      call_perplexity(api_key, question)
    end
  end

  defp call_perplexity(api_key, question) do
    body = %{
      model: "sonar",
      messages: [
        %{role: "system", content: "Answer concisely and directly."},
        %{role: "user", content: question.prompt}
      ],
      max_tokens: 1024
    }

    case Req.post("https://api.perplexity.ai/chat/completions",
           json: body,
           headers: [{"authorization", "Bearer #{api_key}"}],
           receive_timeout: 30_000
         ) do
      {:ok, %{status: 200, body: resp}} ->
        answer = get_in(resp, ["choices", Access.at(0), "message", "content"]) || ""
        tokens_in = get_in(resp, ["usage", "prompt_tokens"]) || 0
        tokens_out = get_in(resp, ["usage", "completion_tokens"]) || 0

        {:ok, %{answer: answer, tokens_in: tokens_in, tokens_out: tokens_out}}

      {:ok, %{status: status, body: resp_body}} ->
        {:error, {:perplexity_error, status, resp_body}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end
end
