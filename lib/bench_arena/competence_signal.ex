defmodule BenchArena.CompetenceSignal do
  @moduledoc """
  Maps confidence_vector through CertaintyVocabulary to a constrained
  output vocabulary gate for the stack adapter's synthesis step.

  Mirrors CSC.CompetenceSignal — the canonical implementation lives in
  composable-skill-compiler. This module is the BenchArena-local copy
  used at evaluation time.

  Addresses FINRA's 'Competence Simulation Risk' (P4d).
  """

  @vocabulary_constraints %{
    verified: %{may_assert: true, must_hedge: false, must_cite: true, may_synthesise: true},
    high_confidence: %{may_assert: true, must_hedge: false, must_cite: true, may_synthesise: true},
    moderate: %{may_assert: false, must_hedge: true, must_cite: true, may_synthesise: true},
    uncertain: %{may_assert: false, must_hedge: true, must_cite: true, may_synthesise: false},
    halted: %{may_assert: false, must_hedge: false, must_cite: false, may_synthesise: false}
  }

  @doc "Classify a confidence score into a certainty vocabulary level."
  @spec classify(float()) :: atom()
  def classify(confidence) when is_number(confidence) and confidence >= 0.95, do: :verified
  def classify(confidence) when is_number(confidence) and confidence >= 0.80, do: :high_confidence
  def classify(confidence) when is_number(confidence) and confidence >= 0.60, do: :moderate
  def classify(confidence) when is_number(confidence) and confidence >= 0.40, do: :uncertain
  def classify(_), do: :halted

  @doc "Returns the vocabulary constraints for a given certainty vocabulary level."
  @spec constraints_for(atom()) :: map()
  def constraints_for(certainty_vocab) do
    Map.get(@vocabulary_constraints, certainty_vocab, @vocabulary_constraints.halted)
  end

  @doc """
  Inject the CompetenceSignal into a synthesis prompt.

  Given a prompt and a list of confidence scores (one per upstream step),
  returns either:
  - `{:halt, :competence_signal, info}` if synthesis should be blocked
  - `{:ok, vocab, modified_prompt}` with the competence-gated prompt
  """
  @spec inject_into_prompt(String.t(), [float()]) ::
          {:halt, :competence_signal, map()} | {:ok, atom(), String.t()}
  def inject_into_prompt(prompt, confidence_vector) do
    min_confidence = Enum.min(confidence_vector, fn -> 1.0 end)
    vocab = classify(min_confidence)
    constraints = constraints_for(vocab)

    cond do
      not constraints.may_synthesise ->
        {:halt, :competence_signal, %{min_confidence: min_confidence, vocab: vocab}}

      constraints.must_hedge ->
        prefix =
          "Based on available evidence (confidence: #{Float.round(min_confidence, 2)}), " <>
            "and noting this assessment is uncertain and should be reviewed by a qualified professional: "

        {:ok, vocab, prefix <> prompt}

      constraints.may_assert ->
        {:ok, vocab, prompt}
    end
  end
end
