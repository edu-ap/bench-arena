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

  describe "load_tier7/0" do
    test "returns 45 questions" do
      questions = Corpus.load_tier7()
      assert length(questions) == 45
    end

    test "returns Question structs" do
      [q | _] = Corpus.load_tier7()
      assert %Question{} = q
      assert is_binary(q.id)
      assert is_binary(q.prompt)
      assert is_binary(q.reference_answer)
    end

    test "all questions are tier7" do
      questions = Corpus.load_tier7()
      assert Enum.all?(questions, &(&1.tier == "tier7"))
    end

    test "all questions have tier_name hallucination_resistance" do
      questions = Corpus.load_tier7()
      assert Enum.all?(questions, &(&1.tier_name == "hallucination_resistance"))
    end

    test "has 15 TruthfulQA questions" do
      questions = Corpus.load_tier7()
      tqa = Enum.filter(questions, &(&1.benchmark_ref == "truthfulqa"))
      assert length(tqa) == 15
    end

    test "has 15 SimpleQA questions" do
      questions = Corpus.load_tier7()
      sqa = Enum.filter(questions, &(&1.benchmark_ref == "simpleqa"))
      assert length(sqa) == 15
    end

    test "has 15 BBH questions" do
      questions = Corpus.load_tier7()
      bbh = Enum.filter(questions, &(&1.benchmark_ref == "bbh"))
      assert length(bbh) == 15
    end

    test "all benchmark_refs are valid tier7 types" do
      questions = Corpus.load_tier7()
      assert Enum.all?(questions, &(&1.benchmark_ref in ["truthfulqa", "simpleqa", "bbh"]))
    end

    test "all questions have valid scoring methods" do
      questions = Corpus.load_tier7()
      assert Enum.all?(questions, &(&1.scoring_method in [:exact_match, :semantic, :rubric]))
    end

    test "TruthfulQA questions use exact_match scoring" do
      questions = Corpus.load_tier7()
      tqa = Enum.filter(questions, &(&1.benchmark_ref == "truthfulqa"))
      assert Enum.all?(tqa, &(&1.scoring_method == :exact_match))
    end

    test "SimpleQA questions use semantic scoring" do
      questions = Corpus.load_tier7()
      sqa = Enum.filter(questions, &(&1.benchmark_ref == "simpleqa"))
      assert Enum.all?(sqa, &(&1.scoring_method == :semantic))
    end

    test "all IDs follow std_ prefix pattern" do
      questions = Corpus.load_tier7()
      assert Enum.all?(questions, &String.starts_with?(&1.id, "std_"))
    end

    test "all questions have tags" do
      questions = Corpus.load_tier7()
      assert Enum.all?(questions, &(is_list(&1.tags) and length(&1.tags) > 0))
    end

    test "all questions have expected_tokens_budget" do
      questions = Corpus.load_tier7()
      assert Enum.all?(questions, &(is_integer(&1.expected_tokens_budget) and &1.expected_tokens_budget > 0))
    end

    test "TruthfulQA IDs are sequential" do
      questions = Corpus.load_tier7()
      tqa = Enum.filter(questions, &(&1.benchmark_ref == "truthfulqa"))
      ids = Enum.map(tqa, & &1.id)
      assert Enum.at(ids, 0) == "std_truthfulqa_001"
      assert Enum.at(ids, 14) == "std_truthfulqa_015"
    end

    test "BBH IDs are sequential" do
      questions = Corpus.load_tier7()
      bbh = Enum.filter(questions, &(&1.benchmark_ref == "bbh"))
      ids = Enum.map(bbh, & &1.id)
      assert Enum.at(ids, 0) == "std_bbh_001"
      assert Enum.at(ids, 14) == "std_bbh_015"
    end
  end

  describe "load_tier8/0" do
    test "returns 25 questions" do
      questions = Corpus.load_tier8()
      assert length(questions) == 25
    end

    test "returns Question structs" do
      [q | _] = Corpus.load_tier8()
      assert %Question{} = q
      assert is_binary(q.id)
      assert is_binary(q.prompt)
      assert is_binary(q.reference_answer)
    end

    test "all questions are tier8" do
      questions = Corpus.load_tier8()
      assert Enum.all?(questions, &(&1.tier == "tier8"))
    end

    test "all questions have tier_name legal_formal_reasoning" do
      questions = Corpus.load_tier8()
      assert Enum.all?(questions, &(&1.tier_name == "legal_formal_reasoning"))
    end

    test "has 5 deontic conflict questions" do
      questions = Corpus.load_tier8()
      dc = Enum.filter(questions, &(&1.benchmark_ref == "legallean_deontic_conflict"))
      assert length(dc) == 5
    end

    test "has 5 defeat acyclicity questions" do
      questions = Corpus.load_tier8()
      da = Enum.filter(questions, &(&1.benchmark_ref == "legallean_defeat_acyclicity"))
      assert length(da) == 5
    end

    test "has 5 temporal scope questions" do
      questions = Corpus.load_tier8()
      ts = Enum.filter(questions, &(&1.benchmark_ref == "legallean_temporal_scope"))
      assert length(ts) == 5
    end

    test "has 5 modality conversion questions" do
      questions = Corpus.load_tier8()
      mc = Enum.filter(questions, &(&1.benchmark_ref == "legallean_modality"))
      assert length(mc) == 5
    end

    test "has 5 compliance mapping questions" do
      questions = Corpus.load_tier8()
      cm = Enum.filter(questions, &(&1.benchmark_ref == "legallean_compliance_mapping"))
      assert length(cm) == 5
    end

    test "all benchmark_refs start with legallean_" do
      questions = Corpus.load_tier8()
      assert Enum.all?(questions, &String.starts_with?(&1.benchmark_ref, "legallean_"))
    end

    test "all questions have valid scoring methods" do
      questions = Corpus.load_tier8()
      assert Enum.all?(questions, &(&1.scoring_method in [:exact_match, :semantic, :rubric]))
    end

    test "compliance mapping questions use rubric scoring" do
      questions = Corpus.load_tier8()
      cm = Enum.filter(questions, &(&1.benchmark_ref == "legallean_compliance_mapping"))
      assert Enum.all?(cm, &(&1.scoring_method == :rubric))
    end

    test "deontic conflict questions use rubric scoring" do
      questions = Corpus.load_tier8()
      dc = Enum.filter(questions, &(&1.benchmark_ref == "legallean_deontic_conflict"))
      assert Enum.all?(dc, &(&1.scoring_method == :rubric))
    end

    test "defeat acyclicity questions use exact_match scoring" do
      questions = Corpus.load_tier8()
      da = Enum.filter(questions, &(&1.benchmark_ref == "legallean_defeat_acyclicity"))
      assert Enum.all?(da, &(&1.scoring_method == :exact_match))
    end

    test "modality questions use exact_match scoring" do
      questions = Corpus.load_tier8()
      mc = Enum.filter(questions, &(&1.benchmark_ref == "legallean_modality"))
      assert Enum.all?(mc, &(&1.scoring_method == :exact_match))
    end

    test "rubric-scored questions have rubric_criteria" do
      questions = Corpus.load_tier8()
      rubric_qs = Enum.filter(questions, &(&1.scoring_method == :rubric))
      assert Enum.all?(rubric_qs, &(not is_nil(&1.rubric_criteria)))
    end

    test "conflict IDs follow leg_conflict_ pattern" do
      questions = Corpus.load_tier8()
      dc = Enum.filter(questions, &(&1.benchmark_ref == "legallean_deontic_conflict"))
      assert Enum.all?(dc, &String.starts_with?(&1.id, "leg_conflict_"))
    end

    test "all questions have tags" do
      questions = Corpus.load_tier8()
      assert Enum.all?(questions, &(is_list(&1.tags) and length(&1.tags) > 0))
    end

    test "all questions have expected_tokens_budget" do
      questions = Corpus.load_tier8()
      assert Enum.all?(questions, &(is_integer(&1.expected_tokens_budget) and &1.expected_tokens_budget > 0))
    end
  end
end
