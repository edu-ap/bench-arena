
# Phase 2A: Stack BBH remaining (11q) + Tier 8 baseline + standard (fast adapters)
# Stack BBH: 11q × 12s = ~132s
# Tier 8 baseline: 25q × ~0s = instant
# Tier 8 standard: 25q × 4s = ~100s
# Total: ~240s

Application.ensure_all_started(:bench_arena)
alias BenchArena.{Runner, Corpus, Scorer}

tier7_all = Corpus.load_tier7()
tier7_bbh = Enum.filter(tier7_all, &(&1.benchmark_ref == "bbh"))
tier8 = Corpus.load_tier8()

# BBH questions stack already ran (4 questions)
bbh_already_ran = ["std_bbh_001", "std_bbh_002", "std_bbh_003", "std_bbh_004"]
bbh_remaining = Enum.filter(tier7_bbh, fn q -> q.id not in bbh_already_ran end)

IO.puts("BBH remaining for stack: #{length(bbh_remaining)}q")
IO.puts("Tier 8: #{length(tier8)}q")

all_results = []

# BBH stack remaining
IO.puts("\n=== BBH (stack remaining) ===")
bbh_results =
  Enum.map(bbh_remaining, fn q ->
    IO.write("  [#{q.id}] ")
    result = Runner.run_question(q, :stack)
    answer = result.answer || ""
    score = Scorer.score(answer, q)
    IO.puts("#{Float.round(result.latency_ms / 1000, 2)}s | #{Float.round(score, 2)}")
    %{
      "adapter" => "stack",
      "question_id" => q.id,
      "benchmark_ref" => q.benchmark_ref,
      "tier" => q.tier,
      "score" => score,
      "latency_ms" => result.latency_ms,
      "total_tokens" => result.total_tokens,
      "error" => if(result.error, do: inspect(result.error))
    }
  end)

IO.puts("BBH stack done: #{length(bbh_results)} results")

# Tier 8 baseline (fast — stub echoes reference)
IO.puts("\n=== Tier 8 (baseline) ===")
t8_baseline =
  Enum.map(tier8, fn q ->
    IO.write("  [#{q.id}] ")
    result = Runner.run_question(q, :baseline)
    answer = result.answer || ""
    score = Scorer.score(answer, q)
    IO.puts("score=#{Float.round(score, 2)}")
    %{
      "adapter" => "baseline",
      "question_id" => q.id,
      "benchmark_ref" => q.benchmark_ref,
      "tier" => q.tier,
      "score" => score,
      "latency_ms" => result.latency_ms,
      "total_tokens" => result.total_tokens,
      "error" => if(result.error, do: inspect(result.error))
    }
  end)

IO.puts("Tier 8 baseline done: #{length(t8_baseline)} results")

# Tier 8 standard
IO.puts("\n=== Tier 8 (perplexity_standard) ===")
t8_standard =
  Enum.map(tier8, fn q ->
    IO.write("  [#{q.id}] ")
    result = Runner.run_question(q, :perplexity_standard)
    answer = result.answer || ""
    score = Scorer.score(answer, q)
    IO.puts("#{Float.round(result.latency_ms / 1000, 2)}s | #{Float.round(score, 2)}")
    %{
      "adapter" => "perplexity_standard",
      "question_id" => q.id,
      "benchmark_ref" => q.benchmark_ref,
      "tier" => q.tier,
      "score" => score,
      "latency_ms" => result.latency_ms,
      "total_tokens" => result.total_tokens,
      "error" => if(result.error, do: inspect(result.error))
    }
  end)

IO.puts("Tier 8 standard done: #{length(t8_standard)} results")

all_results = bbh_results ++ t8_baseline ++ t8_standard
File.write!("bench_results/fixup_p2.json", Jason.encode!(all_results, pretty: true))
IO.puts("\nSaved #{length(all_results)} results to bench_results/fixup_p2.json")
