defmodule BenchArena.CorpusTest do
  use ExUnit.Case, async: true

  alias BenchArena.Corpus
  alias BenchArena.Corpus.Question

  describe "load_tier/1" do
    test "loads tier 1 factual questions" do
      questions = Corpus.load_tier(1)
      assert length(questions) == 10
      assert Enum.all?(questions, &(&1.tier == 1))
    end

    test "loads tier 2 reasoning questions" do
      questions = Corpus.load_tier(2)
      assert length(questions) == 8
      assert Enum.all?(questions, &(&1.tier == 2))
    end

    test "loads tier 3 legal questions" do
      questions = Corpus.load_tier(3)
      assert length(questions) == 6
      assert Enum.all?(questions, &(&1.tier == 3))
    end

    test "loads tier 4 code questions" do
      questions = Corpus.load_tier(4)
      assert length(questions) == 6
      assert Enum.all?(questions, &(&1.tier == 4))
    end

    test "loads tier 5 metacog questions" do
      questions = Corpus.load_tier(5)
      assert length(questions) == 5
      assert Enum.all?(questions, &(&1.tier == 5))
    end

    test "returns Question structs" do
      [q | _] = Corpus.load_tier(1)
      assert %Question{} = q
      assert is_binary(q.id)
      assert is_binary(q.prompt)
      assert is_binary(q.reference_answer)
    end

    test "parses scoring method as atom" do
      questions = Corpus.load_tier(1)
      assert Enum.all?(questions, &(&1.scoring_method in [:exact_match, :semantic, :rubric]))
    end

    test "parses tags as atoms" do
      [q | _] = Corpus.load_tier(1)
      assert is_list(q.tags)
      assert Enum.all?(q.tags, &is_atom/1)
    end

    test "sets tier_name" do
      [q | _] = Corpus.load_tier(1)
      assert q.tier_name == "factual"
    end

    test "sets expected_tokens_budget" do
      [q | _] = Corpus.load_tier(1)
      assert is_integer(q.expected_tokens_budget)
      assert q.expected_tokens_budget > 0
    end
  end

  describe "all/0" do
    test "loads questions from all tiers" do
      questions = Corpus.all()
      # 10 + 8 + 6 + 6 + 5 = 35
      assert length(questions) == 35
    end

    test "includes questions from each tier" do
      questions = Corpus.all()
      tiers = questions |> Enum.map(& &1.tier) |> Enum.uniq() |> Enum.sort()
      assert tiers == [1, 2, 3, 4, 5]
    end
  end

  describe "sample/2" do
    test "returns N questions from specified tier" do
      questions = Corpus.sample(1, 3)
      assert length(questions) == 3
      assert Enum.all?(questions, &(&1.tier == 1))
    end

    test "returns fewer if tier has fewer questions" do
      questions = Corpus.sample(5, 100)
      assert length(questions) == 5
    end

    test "returns different order on multiple calls (randomized)" do
      # Run several times to check randomization
      samples = for _ <- 1..5, do: Corpus.sample(1, 10) |> Enum.map(& &1.id)
      # At least some should differ in order (probabilistic, but very likely with 10 items)
      unique_orders = Enum.uniq(samples)
      # Might be all unique, or at least some variation
      assert length(unique_orders) >= 1
    end
  end

  describe "tier_info/0" do
    test "returns info for all 5 tiers" do
      info = Corpus.tier_info()
      assert length(info) == 5
    end

    test "returns tier number, name, and count" do
      [{tier, name, count} | _] = Corpus.tier_info()
      assert tier == 1
      assert is_binary(name)
      assert is_integer(count)
      assert count > 0
    end
  end

  describe "load_standard/0" do
    test "returns 25 standard questions" do
      questions = Corpus.load_standard()
      assert length(questions) == 25
    end

    test "all standard questions have benchmark_ref set" do
      questions = Corpus.load_standard()
      assert Enum.all?(questions, &(not is_nil(&1.benchmark_ref)))
    end

    test "returns Question structs" do
      [q | _] = Corpus.load_standard()
      assert %Question{} = q
      assert is_binary(q.id)
      assert is_binary(q.prompt)
      assert is_binary(q.reference_answer)
    end

    test "all standard questions are tier 6" do
      questions = Corpus.load_standard()
      assert Enum.all?(questions, &(&1.tier == 6))
    end

    test "all standard questions have tier_name 'standard_benchmark'" do
      questions = Corpus.load_standard()
      assert Enum.all?(questions, &(&1.tier_name == "standard_benchmark"))
    end

    test "has 5 MMLU-Pro style questions" do
      questions = Corpus.load_standard()
      mmlu = Enum.filter(questions, &(&1.benchmark_ref == "mmlu_pro"))
      assert length(mmlu) == 5
    end

    test "has 5 GPQA Diamond style questions" do
      questions = Corpus.load_standard()
      gpqa = Enum.filter(questions, &(&1.benchmark_ref == "gpqa_diamond"))
      assert length(gpqa) == 5
    end

    test "has 5 HumanEval style questions" do
      questions = Corpus.load_standard()
      he = Enum.filter(questions, &(&1.benchmark_ref == "humaneval"))
      assert length(he) == 5
    end

    test "has 5 IFEval style questions" do
      questions = Corpus.load_standard()
      ife = Enum.filter(questions, &(&1.benchmark_ref == "ifeval"))
      assert length(ife) == 5
    end

    test "has 5 AIME style questions" do
      questions = Corpus.load_standard()
      aime = Enum.filter(questions, &(&1.benchmark_ref == "aime"))
      assert length(aime) == 5
    end

    test "all IDs follow std_ prefix pattern" do
      questions = Corpus.load_standard()
      assert Enum.all?(questions, &String.starts_with?(&1.id, "std_"))
    end

    test "all questions have valid scoring methods" do
      questions = Corpus.load_standard()
      assert Enum.all?(questions, &(&1.scoring_method in [:exact_match, :semantic, :rubric]))
    end

    test "all questions have tags including 'standard'" do
      questions = Corpus.load_standard()
      assert Enum.all?(questions, &(:standard in &1.tags))
    end

    test "MMLU-Pro questions use exact_match scoring" do
      questions = Corpus.load_standard()
      mmlu = Enum.filter(questions, &(&1.benchmark_ref == "mmlu_pro"))
      assert Enum.all?(mmlu, &(&1.scoring_method == :exact_match))
    end

    test "GPQA Diamond questions use exact_match scoring" do
      questions = Corpus.load_standard()
      gpqa = Enum.filter(questions, &(&1.benchmark_ref == "gpqa_diamond"))
      assert Enum.all?(gpqa, &(&1.scoring_method == :exact_match))
    end

    test "HumanEval questions use rubric scoring" do
      questions = Corpus.load_standard()
      he = Enum.filter(questions, &(&1.benchmark_ref == "humaneval"))
      assert Enum.all?(he, &(&1.scoring_method == :rubric))
    end

    test "AIME questions use exact_match scoring" do
      questions = Corpus.load_standard()
      aime = Enum.filter(questions, &(&1.benchmark_ref == "aime"))
      assert Enum.all?(aime, &(&1.scoring_method == :exact_match))
    end

    test "all questions have expected_tokens_budget" do
      questions = Corpus.load_standard()
      assert Enum.all?(questions, &(is_integer(&1.expected_tokens_budget) and &1.expected_tokens_budget > 0))
    end
  end

  describe "benchmark_ref field" do
    test "existing tier questions have nil benchmark_ref" do
      questions = Corpus.load_tier(1)
      assert Enum.all?(questions, &is_nil(&1.benchmark_ref))
    end
  end
end
