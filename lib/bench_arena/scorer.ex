defmodule BenchArena.Scorer do
  @moduledoc """
  Accuracy scoring with three methods: exact_match, semantic (Jaccard), and rubric.
  """

  alias BenchArena.Corpus.Question

  @doc """
  Score an answer against a question's reference answer.
  Returns a float between 0.0 and 1.0.
  """
  @spec score(String.t(), Question.t()) :: float()
  def score(answer, %Question{} = question) do
    case question.scoring_method do
      :exact_match -> exact_match(answer, question.reference_answer)
      :semantic -> semantic_score(answer, question.reference_answer)
      :rubric -> rubric_score(answer, question.rubric)
    end
  end

  @doc """
  Batch score a list of {answer, question} pairs.
  """
  @spec batch_score([{String.t(), Question.t()}]) :: [float()]
  def batch_score(pairs) when is_list(pairs) do
    Enum.map(pairs, fn {answer, question} -> score(answer, question) end)
  end

  @doc """
  Compute calibration: correlation between predicted scores and actual correctness.
  Returns %{mean_score, count, score_distribution}.
  """
  @spec calibration([float()]) :: map()
  def calibration(scores) when is_list(scores) do
    count = length(scores)

    if count == 0 do
      %{mean_score: 0.0, count: 0, score_distribution: %{}}
    else
      mean = Enum.sum(scores) / count

      distribution =
        scores
        |> Enum.map(&bucket/1)
        |> Enum.frequencies()

      %{
        mean_score: Float.round(mean, 4),
        count: count,
        score_distribution: distribution
      }
    end
  end

  @doc """
  Exact match scoring: normalize and compare strings.
  For single-letter MCQ references (A-J), extracts the letter from natural-language answers.
  For short integer references (0-999, AIME style), extracts the number from answers.
  Returns 0.0 or 1.0.
  """
  @spec exact_match(String.t(), String.t()) :: float()
  def exact_match(answer, reference) do
    cond do
      # Single-letter MCQ (A-J)
      String.match?(reference, ~r/^[A-J]$/) ->
        extracted = extract_mcq_letter(answer)
        if extracted == reference, do: 1.0, else: 0.0

      # Short integer answer 0-999 (AIME style)
      String.match?(reference, ~r/^\d{1,3}$/) ->
        extracted = extract_integer(answer)
        if extracted == reference, do: 1.0, else: 0.0

      # Default: normalized full string match
      true ->
        if normalize(answer) == normalize(reference), do: 1.0, else: 0.0
    end
  end

  @doc """
  Extract a single MCQ letter (A-J) from a natural-language answer.
  Handles **B)**, **B**, "option B", "answer is B", leading letter, etc.
  """
  @spec extract_mcq_letter(String.t()) :: String.t() | nil
  def extract_mcq_letter(answer) when is_binary(answer) do
    cond do
      # **X)** bold with paren — most common pattern
      m = Regex.run(~r/\*\*([A-J])\)/, answer) -> Enum.at(m, 1)
      # **X** bold without paren
      m = Regex.run(~r/\*\*([A-J])\*\*/, answer) -> Enum.at(m, 1)
      # "option X", "answer is X", "correct answer is X", "choice X"
      m = Regex.run(~r/(?:option|answer is|correct answer is|choice|select)\s+\*?\*?([A-J])\b/i, answer) -> Enum.at(m, 1)
      # Leading letter at start of answer: "B) ..." or "B. ..."
      m = Regex.run(~r/^\s*([A-J])[\)\.]\s/, answer) -> Enum.at(m, 1)
      true -> nil
    end
  end

  def extract_mcq_letter(_), do: nil

  @doc """
  Extract a short integer (0-999) from a natural-language answer.
  Handles **143**, bold integers, or standalone numbers.
  """
  @spec extract_integer(String.t()) :: String.t() | nil
  def extract_integer(answer) when is_binary(answer) do
    cond do
      # **NNN** bold integer
      m = Regex.run(~r/\*\*(\d{1,3})\*\*/, answer) ->
        val = String.to_integer(Enum.at(m, 1))
        if val in 0..999, do: to_string(val), else: nil

      # Standalone 1-3 digit number (prefer the first one found)
      m = Regex.run(~r/\b(\d{1,3})\b/, answer) ->
        val = String.to_integer(Enum.at(m, 1))
        if val in 0..999, do: to_string(val), else: nil

      true -> nil
    end
  end

  def extract_integer(_), do: nil

  @doc """
  Semantic scoring: compute token overlap using Jaccard similarity on lowercased word sets.
  Returns 0.0 to 1.0.
  """
  @spec semantic_score(String.t(), String.t()) :: float()
  def semantic_score(answer, reference) do
    # Containment-first: if reference is a short phrase (≤5 words) and it appears
    # verbatim inside the answer, score 1.0. This fixes SimpleQA where models answer
    # in prose but the reference is a proper noun or short fact.
    ref_words = reference |> String.split(~r/\s+/, trim: true) |> length()

    if ref_words <= 5 and
         String.contains?(
           String.downcase(answer),
           String.downcase(reference)
         ) do
      1.0
    else
      # Fallback: Jaccard token-overlap
      answer_words = tokenize(answer)
      reference_words = tokenize(reference)

      if MapSet.size(answer_words) == 0 and MapSet.size(reference_words) == 0 do
        1.0
      else
        intersection = MapSet.intersection(answer_words, reference_words) |> MapSet.size()
        union = MapSet.union(answer_words, reference_words) |> MapSet.size()

        if union == 0, do: 0.0, else: intersection / union
      end
    end
  end

  @doc """
  Rubric-based scoring: evaluate against criteria.
  Returns mean score across all criteria (0.0 to 1.0).
  """
  @spec rubric_score(String.t(), map() | nil) :: float()
  def rubric_score(_answer, nil), do: 0.0

  def rubric_score(answer, rubric) when is_map(rubric) do
    criteria = Map.get(rubric, "criteria", Map.get(rubric, :criteria, []))
    max_score = Map.get(rubric, "max_score", Map.get(rubric, :max_score, length(criteria)))

    if criteria == [] or max_score == 0 do
      0.0
    else
      scores =
        Enum.map(criteria, fn criterion ->
          keyword = extract_keyword(criterion)
          if keyword != "" and String.contains?(String.downcase(answer), String.downcase(keyword)) do
            1.0
          else
            0.0
          end
        end)

      total = Enum.sum(scores)
      Float.round(min(total / max_score, 1.0), 4)
    end
  end

  # Private helpers

  defp normalize(str) when is_binary(str) do
    str
    |> String.downcase()
    |> String.trim()
    |> String.replace(~r/\s+/, " ")
    |> String.replace(~r/[^\w\s]/, "")
  end

  defp normalize(_), do: ""

  defp tokenize(str) when is_binary(str) do
    str
    |> String.downcase()
    |> String.replace(~r/[^\w\s]/, " ")
    |> String.split(~r/\s+/, trim: true)
    |> MapSet.new()
  end

  defp tokenize(_), do: MapSet.new()

  defp extract_keyword(criterion) when is_binary(criterion), do: criterion

  defp extract_keyword(criterion) when is_map(criterion) do
    Map.get(criterion, "keyword", Map.get(criterion, :keyword, ""))
  end

  defp extract_keyword(_), do: ""

  defp bucket(score) when score >= 0.9, do: "0.9-1.0"
  defp bucket(score) when score >= 0.7, do: "0.7-0.9"
  defp bucket(score) when score >= 0.5, do: "0.5-0.7"
  defp bucket(score) when score >= 0.3, do: "0.3-0.5"
  defp bucket(_score), do: "0.0-0.3"
end
