defmodule BenchArena.Adapters.PerplexityModelCouncilAdapter do
  @moduledoc """
  Simulates Perplexity's "model council" — queries the same question against
  `sonar-pro` and `sonar-reasoning-pro`, then synthesises the answers into
  one concise final answer using a third call.
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
        run_council(api_key, question)
    end
  end

  defp get_api_key do
    Application.get_env(:bench_arena, :perplexity_api_key) ||
      System.get_env("PERPLEXITY_API_KEY")
  end

  defp run_council(api_key, question) do
    with {:ok, answer_a, tokens_a} <- query_model(api_key, "sonar-pro", question.prompt),
         {:ok, answer_b, tokens_b} <- query_model(api_key, "sonar-reasoning-pro", question.prompt),
         {:ok, synthesis, tokens_c} <- synthesise(api_key, answer_a, answer_b, question.prompt) do
      total_in = tokens_a.in + tokens_b.in + tokens_c.in
      total_out = tokens_a.out + tokens_b.out + tokens_c.out

      {:ok, %{answer: synthesis, tokens_in: total_in, tokens_out: total_out}}
    end
  end

  defp query_model(api_key, model, prompt) do
    body = %{
      model: model,
      messages: [%{role: "user", content: prompt}],
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

        {:ok, answer, %{in: tokens_in, out: tokens_out}}

      {:ok, %{status: status, body: resp_body}} ->
        {:error, {:api_error, status, resp_body}}

      {:error, %{reason: reason}} ->
        {:error, {:request_failed, reason}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  defp synthesise(api_key, answer_a, answer_b, prompt) do
    body = %{
      model: "sonar-pro",
      messages: [
        %{
          role: "system",
          content:
            "You are a synthesis judge. You have two expert answers. Produce one concise final answer."
        },
        %{
          role: "user",
          content: "Answer A: #{answer_a}\n\nAnswer B: #{answer_b}\n\nQuestion: #{prompt}"
        }
      ],
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

        {:ok, answer, %{in: tokens_in, out: tokens_out}}

      {:ok, %{status: status, body: resp_body}} ->
        {:error, {:api_error, status, resp_body}}

      {:error, %{reason: reason}} ->
        {:error, {:request_failed, reason}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end
end
