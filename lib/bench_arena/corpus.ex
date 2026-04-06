defmodule BenchArena.Corpus do
  @moduledoc """
  Question bank loader. Reads from priv/corpus/*.json.
  """

  defmodule Question do
    @moduledoc "A benchmark question."

    defstruct [
      :id,
      :tier,
      :tier_name,
      :prompt,
      :reference_answer,
      :scoring_method,
      :rubric,
      :tags,
      :expected_tokens_budget,
      :benchmark_ref
    ]

    @type t :: %__MODULE__{
            id: String.t(),
            tier: integer(),
            tier_name: String.t(),
            prompt: String.t(),
            reference_answer: String.t(),
            scoring_method: :exact_match | :semantic | :rubric,
            rubric: map() | nil,
            tags: [atom()],
            expected_tokens_budget: integer(),
            benchmark_ref: String.t() | nil
          }
  end

  @corpus_dir "priv/corpus"

  @tier_files %{
    1 => "tier1_factual.json",
    2 => "tier2_reasoning.json",
    3 => "tier3_legal.json",
    4 => "tier4_code.json",
    5 => "tier5_metacog.json"
  }

  @doc """
  Load all questions for a specific tier.
  """
  @spec load_tier(integer()) :: [Question.t()]
  def load_tier(tier) when tier in 1..5 do
    file = Map.fetch!(@tier_files, tier)
    path = corpus_path(file)

    case File.read(path) do
      {:ok, content} ->
        content
        |> Jason.decode!()
        |> Map.get("questions", [])
        |> Enum.map(&parse_question/1)

      {:error, _} ->
        []
    end
  end

  @doc """
  Load all questions across all tiers.
  """
  @spec all() :: [Question.t()]
  def all do
    Enum.flat_map(1..5, &load_tier/1)
  end

  @doc """
  Random sample of N questions from a tier.
  """
  @spec sample(integer(), integer()) :: [Question.t()]
  def sample(tier, n) when tier in 1..5 and is_integer(n) and n > 0 do
    tier
    |> load_tier()
    |> Enum.shuffle()
    |> Enum.take(n)
  end

  @doc """
  Load the standard benchmark-aligned question set from priv/corpus/standard_questions.json.
  Returns 25 questions aligned with MMLU-Pro, GPQA Diamond, HumanEval, IFEval, and AIME.
  """
  @spec load_standard() :: [Question.t()]
  def load_standard do
    path = corpus_path("standard_questions.json")

    case File.read(path) do
      {:ok, content} ->
        content
        |> Jason.decode!()
        |> Map.get("questions", [])
        |> Enum.map(&parse_question/1)

      {:error, _} ->
        []
    end
  end

  @doc """
  List available tiers and question counts.
  """
  @spec tier_info() :: [{integer(), String.t(), integer()}]
  def tier_info do
    Enum.map(1..5, fn tier ->
      questions = load_tier(tier)
      tier_name = if questions != [], do: hd(questions).tier_name, else: "unknown"
      {tier, tier_name, length(questions)}
    end)
  end

  defp corpus_path(file) do
    app_dir =
      case :code.priv_dir(:bench_arena) do
        {:error, _} -> @corpus_dir
        dir -> Path.join(to_string(dir), "corpus")
      end

    Path.join(app_dir, file)
  end

  defp parse_question(map) do
    %Question{
      id: map["id"],
      tier: map["tier"],
      tier_name: map["tier_name"],
      prompt: map["prompt"],
      reference_answer: map["reference_answer"],
      scoring_method: parse_scoring_method(map["scoring_method"]),
      rubric: map["rubric"],
      tags: parse_tags(map["tags"]),
      expected_tokens_budget: map["expected_tokens_budget"] || 200,
      benchmark_ref: map["benchmark_ref"]
    }
  end

  defp parse_scoring_method("exact_match"), do: :exact_match
  defp parse_scoring_method("semantic"), do: :semantic
  defp parse_scoring_method("rubric"), do: :rubric
  defp parse_scoring_method(_), do: :exact_match

  defp parse_tags(nil), do: []
  defp parse_tags(tags) when is_list(tags), do: Enum.map(tags, &String.to_atom/1)
  defp parse_tags(_), do: []
end
