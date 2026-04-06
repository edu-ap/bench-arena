defmodule BenchArena.Adapters.BaselineAdapter do
  @moduledoc """
  Baseline adapter: no stack, no loop. Returns a stub answer based on the
  question's reference answer with slight perturbation. Used as a floor comparison.
  Always succeeds, latency ~1ms, tokens = reference answer length / 4.
  """

  @behaviour BenchArena.Adapter

  alias BenchArena.Corpus.Question

  @impl true
  @spec execute(Question.t()) ::
          {:ok, %{answer: String.t(), tokens_in: integer(), tokens_out: integer()}}
  def execute(%Question{} = question) do
    # Simulate minimal latency
    Process.sleep(1)

    answer = perturb_answer(question.reference_answer)
    estimated_tokens = max(div(String.length(question.reference_answer || ""), 4), 1)

    {:ok,
     %{
       answer: answer,
       tokens_in: div(String.length(question.prompt), 4),
       tokens_out: estimated_tokens
     }}
  end

  defp perturb_answer(nil), do: "unknown"

  defp perturb_answer(reference) do
    # Add slight variation: prefix with "approximately" for numeric answers,
    # or return as-is for longer text answers
    cond do
      String.match?(reference, ~r/^\d/) ->
        "approximately #{reference}"

      String.length(reference) < 50 ->
        reference

      true ->
        # For longer answers, return first 80% of content
        len = String.length(reference)
        String.slice(reference, 0, trunc(len * 0.8))
    end
  end
end
