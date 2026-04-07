defmodule BenchArena.ConfabulumRate do
  @moduledoc """
  Confabulum (hallucination) classifier and pipeline gate.

  Classifies LLM outputs across 9 confabulum types and acts as a synthesis gate:
  if any type scores above the halt threshold, synthesis is blocked and a
  `{:halt, type, score}` signal is returned.

  ## Confabulum Types

  The 9-type taxonomy covers the primary failure modes of LLM factual generation:

  - `:factual_error`        — statement contradicts established fact
  - `:temporal_confusion`   — incorrect date/era/sequence
  - `:entity_substitution`  — correct structure, wrong named entity
  - `:causal_inversion`     — cause and effect reversed
  - `:scope_collapse`       — overgeneralisation from specific evidence
  - `:authority_fabrication` — invented citation or authority
  - `:numeric_drift`        — plausible but wrong number
  - `:modal_confusion`      — "is" vs "might be" conflated
  - `:negation_flip`        — negation dropped or inverted

  ## Gate Behaviour

  `gate/2` returns `{:pass, score}` when the aggregate confabulum score is
  below the halt threshold, or `{:halt, type, score}` when the highest-scoring
  type exceeds it.
  """

  @types [
    :factual_error,
    :temporal_confusion,
    :entity_substitution,
    :causal_inversion,
    :scope_collapse,
    :authority_fabrication,
    :numeric_drift,
    :modal_confusion,
    :negation_flip
  ]

  @halt_threshold 0.65

  @doc "Returns the 9 confabulum types."
  @spec types() :: [atom()]
  def types, do: @types

  @doc "Returns the halt threshold."
  @spec halt_threshold() :: float()
  def halt_threshold, do: @halt_threshold

  @doc """
  Score and gate an answer against a question.

  Returns `{:pass, aggregate_score}` if all type scores are below the halt
  threshold, or `{:halt, worst_type, worst_score}` if any type exceeds it.
  """
  @spec gate(String.t(), String.t()) :: {:pass, float()} | {:halt, atom(), float()}
  def gate(answer, question) when is_binary(answer) and is_binary(question) do
    scores = score_all_types(answer, question)

    {worst_type, worst_score} =
      Enum.max_by(scores, fn {_type, score} -> score end)

    if worst_score > @halt_threshold do
      {:halt, worst_type, worst_score}
    else
      aggregate = aggregate_score(scores)
      {:pass, aggregate}
    end
  end

  @doc """
  Score an answer across all 9 confabulum types.

  Returns a keyword list of `{type, score}` pairs.
  """
  @spec score_all_types(String.t(), String.t()) :: [{atom(), float()}]
  def score_all_types(answer, question) do
    Enum.map(@types, fn type ->
      {type, score_type(type, answer, question)}
    end)
  end

  @doc """
  Compute the aggregate confabulum score (weighted mean of all type scores).
  """
  @spec aggregate_score([{atom(), float()}]) :: float()
  def aggregate_score(scores) do
    total = Enum.reduce(scores, 0.0, fn {_type, s}, acc -> acc + s end)
    Float.round(total / length(scores), 4)
  end

  # ---------------------------------------------------------------------------
  # Per-type heuristic scoring
  #
  # Each scorer uses lightweight textual signals. These are fast heuristics,
  # not LLM-based classifiers — designed for pipeline gating where latency
  # matters. Scores range [0.0, 1.0].
  # ---------------------------------------------------------------------------

  @spec score_type(atom(), String.t(), String.t()) :: float()

  defp score_type(:factual_error, answer, _question) do
    # High-confidence hedging markers suggest the model is uncertain about facts
    hedges = ~w(actually incorrect wrong myth false misconception)
    contradictions = ~w(however contrary although despite nevertheless)

    answer_lower = String.downcase(answer)
    hedge_hits = Enum.count(hedges, &String.contains?(answer_lower, &1))
    contra_hits = Enum.count(contradictions, &String.contains?(answer_lower, &1))

    min(1.0, (hedge_hits * 0.1 + contra_hits * 0.05))
  end

  defp score_type(:temporal_confusion, answer, _question) do
    # Look for multiple year references that could indicate confusion
    years = Regex.scan(~r/\b(1[0-9]{3}|20[0-9]{2})\b/, answer) |> List.flatten()

    if length(years) > 3 do
      min(1.0, length(years) * 0.1)
    else
      0.0
    end
  end

  defp score_type(:entity_substitution, _answer, _question) do
    # Without external knowledge base, this requires semantic comparison
    # Default to low score — RAG retrieval handles entity grounding
    0.0
  end

  defp score_type(:causal_inversion, answer, _question) do
    causal_markers = ["because", "causes", "leads to", "results in", "due to"]
    answer_lower = String.downcase(answer)
    hits = Enum.count(causal_markers, &String.contains?(answer_lower, &1))

    # Multiple causal claims increase risk of inversion
    if hits > 2, do: min(1.0, hits * 0.15), else: 0.0
  end

  defp score_type(:scope_collapse, answer, _question) do
    universals = ["always", "never", "all", "none", "every", "no one"]
    answer_lower = String.downcase(answer)
    hits = Enum.count(universals, &String.contains?(answer_lower, &1))

    min(1.0, hits * 0.2)
  end

  defp score_type(:authority_fabrication, answer, _question) do
    # Look for citation-like patterns that could be fabricated
    fake_cite_patterns = [
      ~r/according to (Dr\.|Professor|a study by)/i,
      ~r/published in .+ Journal/i,
      ~r/\(\d{4}\)/
    ]

    hits = Enum.count(fake_cite_patterns, &Regex.match?(&1, answer))
    min(1.0, hits * 0.25)
  end

  defp score_type(:numeric_drift, answer, _question) do
    # Multiple specific numbers increase risk of numeric fabrication
    numbers = Regex.scan(~r/\b\d+\.?\d*%?\b/, answer) |> List.flatten()

    if length(numbers) > 5 do
      min(1.0, length(numbers) * 0.08)
    else
      0.0
    end
  end

  defp score_type(:modal_confusion, answer, _question) do
    # Mixing certainty levels is a confabulum signal
    certain = ["is", "are", "was", "definitely", "certainly", "always"]
    uncertain = ["might", "could", "possibly", "perhaps", "may", "sometimes"]

    answer_lower = String.downcase(answer)
    cert_hits = Enum.count(certain, &String.contains?(answer_lower, &1))
    uncert_hits = Enum.count(uncertain, &String.contains?(answer_lower, &1))

    # Both certain and uncertain language in same answer = modal confusion
    if cert_hits > 0 and uncert_hits > 0 do
      min(1.0, (cert_hits + uncert_hits) * 0.08)
    else
      0.0
    end
  end

  defp score_type(:negation_flip, answer, _question) do
    negations = ["not", "no", "never", "neither", "nor", "don't", "doesn't",
                 "isn't", "aren't", "wasn't", "weren't", "cannot", "can't"]

    answer_lower = String.downcase(answer)
    hits = Enum.count(negations, &String.contains?(answer_lower, &1))

    # Many negations increase risk of a flip
    if hits > 3, do: min(1.0, hits * 0.12), else: 0.0
  end
end
