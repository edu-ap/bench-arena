defmodule BenchArena.Adapters.GeminiCliAdapter do
  @moduledoc """
  Adapter that calls Google Gemini via the Generative Language REST API
  with `gemini-2.5-pro-preview-03-25`.
  """

  @behaviour BenchArena.Adapter

  alias BenchArena.Corpus.Question

  @model "gemini-2.5-pro-preview-03-25"

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
    Application.get_env(:bench_arena, :gemini_api_key) ||
      System.get_env("GEMINI_API_KEY")
  end

  defp call_api(api_key, question) do
    url =
      "https://generativelanguage.googleapis.com/v1beta/models/#{@model}:generateContent?key=#{api_key}"

    body = %{
      contents: [%{parts: [%{text: question.prompt}]}],
      generationConfig: %{maxOutputTokens: 2048}
    }

    case Req.post(url,
           json: body,
           receive_timeout: 30_000,
           retry: false
         ) do
      {:ok, %{status: status, body: resp_body}} when status in 200..299 ->
        answer =
          get_in(resp_body, [
            "candidates",
            Access.at(0),
            "content",
            "parts",
            Access.at(0),
            "text"
          ]) || ""

        tokens_in = get_in(resp_body, ["usageMetadata", "promptTokenCount"]) || 0
        tokens_out = get_in(resp_body, ["usageMetadata", "candidatesTokenCount"]) || 0

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
