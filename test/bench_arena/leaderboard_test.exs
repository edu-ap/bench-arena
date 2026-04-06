defmodule BenchArena.LeaderboardTest do
  use ExUnit.Case, async: true

  alias BenchArena.Leaderboard

  describe "all_scores/0" do
    test "returns a map" do
      scores = Leaderboard.all_scores()
      assert is_map(scores)
    end

    test "contains expected adapters" do
      scores = Leaderboard.all_scores()
      assert Map.has_key?(scores, "claude_code")
      assert Map.has_key?(scores, "gemini_cli")
      assert Map.has_key?(scores, "codex")
      assert Map.has_key?(scores, "perplexity_standard")
      assert Map.has_key?(scores, "perplexity_model_council")
    end

    test "all entries have score, unit, source_url, and accessed" do
      scores = Leaderboard.all_scores()

      Enum.each(scores, fn {_adapter, benchmarks} ->
        Enum.each(benchmarks, fn {_bench, entry} ->
          assert is_number(entry["score"])
          assert is_binary(entry["unit"])
          assert is_binary(entry["source_url"])
          assert is_binary(entry["accessed"])
        end)
      end)
    end

    test "all source_url entries are valid HTTP strings" do
      scores = Leaderboard.all_scores()

      Enum.each(scores, fn {_adapter, benchmarks} ->
        Enum.each(benchmarks, fn {_bench, entry} ->
          assert String.starts_with?(entry["source_url"], "https://")
        end)
      end)
    end

    test "scores are numeric and reasonable" do
      scores = Leaderboard.all_scores()

      Enum.each(scores, fn {_adapter, benchmarks} ->
        Enum.each(benchmarks, fn {_bench, entry} ->
          assert entry["score"] >= 0
          assert entry["score"] <= 100
        end)
      end)
    end
  end

  describe "scores_for/1" do
    test "returns scores for known adapter" do
      scores = Leaderboard.scores_for("claude_code")
      assert is_map(scores)
      assert map_size(scores) > 0
      assert Map.has_key?(scores, "gpqa_diamond")
    end

    test "returns empty map for unknown adapter" do
      scores = Leaderboard.scores_for("nonexistent_adapter")
      assert scores == %{}
    end

    test "returns empty map for nil adapter" do
      scores = Leaderboard.scores_for("")
      assert scores == %{}
    end

    test "returns scores for gemini_cli with multiple benchmarks" do
      scores = Leaderboard.scores_for("gemini_cli")
      assert Map.has_key?(scores, "gpqa_diamond")
      assert Map.has_key?(scores, "swe_bench_verified")
      assert Map.has_key?(scores, "mmlu_pro")
    end

    test "returns scores for perplexity_standard" do
      scores = Leaderboard.scores_for("perplexity_standard")
      assert Map.has_key?(scores, "gpqa_diamond")
      assert Map.has_key?(scores, "mmlu_pro")
      assert Map.has_key?(scores, "live_code_bench")
    end

    test "returns scores for codex" do
      scores = Leaderboard.scores_for("codex")
      assert Map.has_key?(scores, "swe_bench_verified")
    end

    test "each score entry has source_url" do
      scores = Leaderboard.scores_for("claude_code")

      Enum.each(scores, fn {_bench, entry} ->
        assert is_binary(entry["source_url"])
        assert String.starts_with?(entry["source_url"], "https://")
      end)
    end
  end

  describe "benchmark_names/0" do
    test "returns a list of benchmark name strings" do
      names = Leaderboard.benchmark_names()
      assert is_list(names)
      assert length(names) > 0
      assert Enum.all?(names, &is_binary/1)
    end

    test "includes expected benchmarks" do
      names = Leaderboard.benchmark_names()
      assert "gpqa_diamond" in names
      assert "mmlu_pro" in names
      assert "swe_bench_verified" in names
      assert "live_code_bench" in names
    end

    test "returns sorted unique names" do
      names = Leaderboard.benchmark_names()
      assert names == Enum.sort(names)
      assert names == Enum.uniq(names)
    end
  end
end
