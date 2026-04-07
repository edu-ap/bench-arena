Application.ensure_all_started(:bench_arena)

alias BenchArena.{Runner, Corpus, Scorer}

# Adapters that can actually run with PERPLEXITY_API_KEY
live_adapters = [:perplexity_standard, :perplexity_deep_research, :perplexity_model_council]

# Load Tier 1 (factual) + Tier 2 (reasoning) + Tier 6 standard questions
# Skip Tier 3-5 for now (legal/code/metacog are stack-internal, not graded by external models well)
# Use Tier 6 standard questions which map to real public benchmarks
questions_t1 = Corpus.load_tier(1)
questions_t2 = Corpus.load_tier(2)
questions_std = try do
  Corpus.load_standard()
rescue
  _ -> []
end

IO.puts("Tier 1: #{length(questions_t1)} questions")
IO.puts("Tier 2: #{length(questions_t2)} questions")
IO.puts("Standard: #{length(questions_std)} questions")

# Run a subset to keep API costs manageable: 5 T1 + 5 T2 + all 25 standard
sample_t1 = Enum.take(questions_t1, 5)
sample_t2 = Enum.take(questions_t2, 5)
questions = sample_t1 ++ sample_t2 ++ questions_std

IO.puts("\nRunning #{length(questions)} questions × #{length(live_adapters)} adapters = #{length(questions) * length(live_adapters)} total API calls\n")

results = for adapter <- live_adapters do
  IO.puts("=== Adapter: #{adapter} ===")
  adapter_results = for q <- questions do
    IO.write("  [#{q.id}] ")
    result = Runner.run_question(q, adapter)
    answer = result.answer || ""
    score = Scorer.score(answer, q)
    IO.puts("#{Float.round(result.latency_ms / 1000, 1)}s | #{result.total_tokens}tok | score=#{Float.round(score, 2)}")
    %{
      adapter: adapter,
      question_id: q.id,
      tier: q.tier,
      benchmark_ref: q.benchmark_ref,
      latency_ms: result.latency_ms,
      tokens_in: result.tokens_in,
      tokens_out: result.tokens_out,
      total_tokens: result.total_tokens,
      answer: String.slice(answer, 0, 200),
      score: score,
      error: if(result.error, do: inspect(result.error))
    }
  end
  {adapter, adapter_results}
end

# Compute per-adapter summaries
IO.puts("\n\n=== SUMMARY ===\n")
summaries = for {adapter, adapter_results} <- results do
  scored = Enum.filter(adapter_results, &(is_nil(&1.error)))
  errors = Enum.filter(adapter_results, &(!is_nil(&1.error)))

  by_tier = Enum.group_by(adapter_results, & &1.tier)
  tier_scores = Map.new(by_tier, fn {tier, qs} ->
    mean = Enum.sum(Enum.map(qs, & &1.score)) / length(qs)
    {tier, Float.round(mean, 3)}
  end)

  by_benchmark = Enum.group_by(adapter_results, & &1.benchmark_ref)
  bench_scores = Map.new(by_benchmark, fn {bench, qs} ->
    mean = Enum.sum(Enum.map(qs, & &1.score)) / length(qs)
    {bench, Float.round(mean, 3)}
  end)

  overall = Enum.sum(Enum.map(scored, & &1.score)) / max(length(scored), 1)
  avg_latency = Enum.sum(Enum.map(scored, & &1.latency_ms)) / max(length(scored), 1)
  avg_tokens = Enum.sum(Enum.map(scored, & &1.total_tokens)) / max(length(scored), 1)

  IO.puts("#{adapter}:")
  IO.puts("  Overall accuracy: #{Float.round(overall * 100, 1)}%")
  IO.puts("  Avg latency: #{Float.round(avg_latency / 1000, 2)}s")
  IO.puts("  Avg tokens: #{Float.round(avg_tokens, 0)}")
  IO.puts("  Errors: #{length(errors)}")
  IO.puts("  By tier: #{inspect(tier_scores)}")
  IO.puts("  By benchmark: #{inspect(bench_scores)}")
  IO.puts("")

  %{adapter: adapter, overall: overall, avg_latency_ms: avg_latency,
    avg_tokens: avg_tokens, tier_scores: tier_scores, bench_scores: bench_scores,
    errors: length(errors)}
end

# Save to file
File.mkdir_p!("bench_results")
output = %{
  run_id: "real_run_#{Date.utc_today()}",
  run_at: DateTime.utc_now() |> DateTime.to_iso8601(),
  summaries: summaries,
  raw: Enum.flat_map(results, fn {_, r} -> r end)
}
json = Jason.encode!(output, pretty: true)
File.write!("bench_results/real_run.json", json)
IO.puts("Results saved to bench_results/real_run.json")
