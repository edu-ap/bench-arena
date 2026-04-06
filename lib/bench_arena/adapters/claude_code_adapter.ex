defmodule BenchArena.Adapters.ClaudeCodeAdapter do
  @moduledoc """
  Adapter that calls Claude via the Anthropic Messages API with Opus 4.6.
  """

  @behaviour BenchArena.Adapter

  alias BenchArena.Corpus.Question

  @api_url "https://api.anthropic.com/v1/messages"

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
    Application.get_env(:bench_arena, :anthropic_api_key) ||
      System.get_env("ANTHROPIC_API_KEY")
  end

  defp call_api(api_key, question) do
    body = %{
      model: "claude-opus-4-6",
      max_tokens: 2048,
      messages: [%{role: "user", content: question.prompt}]
    }

    case Req.post(@api_url,
           json: body,
           headers: [
             {"x-api-key", api_key},
             {"anthropic-version", "2023-06-01"}
           ],
           receive_timeout: 30_000,
           retry: false
         ) do
      {:ok, %{status: status, body: resp_body}} when status in 200..299 ->
        answer = get_in(resp_body, ["content", Access.at(0), "text"]) || ""
        tokens_in = get_in(resp_body, ["usage", "input_tokens"]) || 0
        tokens_out = get_in(resp_body, ["usage", "output_tokens"]) || 0

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
