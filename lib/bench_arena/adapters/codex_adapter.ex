defmodule BenchArena.Adapters.CodexAdapter do
  @moduledoc """
  Adapter that calls the OpenAI Responses API (Codex/o-series endpoint)
  with the `o4-mini` reasoning model.
  """

  @behaviour BenchArena.Adapter

  alias BenchArena.Corpus.Question

  @api_url "https://api.openai.com/v1/responses"

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
    Application.get_env(:bench_arena, :openai_api_key) ||
      System.get_env("OPENAI_API_KEY")
  end

  defp call_api(api_key, question) do
    body = %{
      model: "o4-mini",
      input: question.prompt,
      reasoning: %{effort: "high"},
      max_output_tokens: 2048
    }

    case Req.post(@api_url,
           json: body,
           headers: [{"authorization", "Bearer #{api_key}"}],
           receive_timeout: 30_000,
           retry: false
         ) do
      {:ok, %{status: status, body: resp_body}} when status in 200..299 ->
        answer = extract_answer(resp_body)
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

  defp extract_answer(%{"output" => output}) when is_list(output) do
    # Skip reasoning items, find the first message content
    output
    |> Enum.reject(fn item -> Map.get(item, "type") == "reasoning" end)
    |> Enum.find_value("", fn item ->
      get_in(item, ["content", Access.at(0), "text"])
    end)
  end

  defp extract_answer(_), do: ""
end
