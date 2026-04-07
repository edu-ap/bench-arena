Application.ensure_all_started(:bench_arena)
alias BenchArena.{Runner, Corpus, Scorer}

# Only run standard questions (Tier 6 — benchmark-aligned)
# Skip deep_research — too slow (20-30s/question). Run standard + model_council only.
live_adapters = [:perplexity_standard, :perplexity_model_council]

questions = try do
  Corpus.load_standard()
rescue
  _ ->
    IO.puts("load_standard/0 not found, trying load_tier(6)")
    try do Corpus.load_tier(6) rescue _ -> [] end
end

IO.puts("Standard questions loaded: #{length(questions)}")
if questions == [], do: raise("No standard questions found!")

IO.puts("Running #{length(questions)} questions × #{length(live_adapters)} adapters\n")

results = for adapter <- live_adapters do
  IO.puts("=== #{adapter} ===")
  adapter_results = for q <- questions do
    IO.write("  [#{q.id}] ")
    result = Runner.run_question(q, adapter)
    answer = result.answer || ""
    score = Scorer.score(answer, q)
    IO.puts("#{Float.round(result.latency_ms / 1000, 2)}s | #{result.total_tokens}tok | score=#{Float.round(score, 2)} | err=#{inspect(result.error)}")
    %{
      adapter: adapter,
      question_id: q.id,
      tier: q.tier,
      benchmark_ref: q.benchmark_ref,
      latency_ms: result.latency_ms,
      tokens_in: result.tokens_in,
      tokens_out: result.tokens_out,
      total_tokens: result.total_tokens,
      answer_preview: String.slice(answer, 0, 150),
      score: score,
      error: if(result.error, do: inspect(result.error))
    }
  end
  {adapter, adapter_results}
end

IO.puts("\n=== SUMMARY ===\n")
summaries = for {adapter, adapter_results} <- results do
  ok = Enum.filter(adapter_results, &is_nil(&1.error))
  errors = length(adapter_results) - length(ok)
  overall = if ok == [], do: 0.0, else: Enum.sum(Enum.map(ok, & &1.score)) / length(ok)
  avg_lat = if ok == [], do: 0.0, else: Enum.sum(Enum.map(ok, & &1.latency_ms)) / length(ok)
  avg_tok = if ok == [], do: 0.0, else: Enum.sum(Enum.map(ok, & &1.total_tokens)) / length(ok)

  by_bench = Enum.group_by(ok, & &1.benchmark_ref)
  bench_scores = Map.new(by_bench, fn {b, qs} ->
    {b, Float.round(Enum.sum(Enum.map(qs, & &1.score)) / length(qs) * 100, 1)}
  end)

  IO.puts("#{adapter}:")
  IO.puts("  Overall: #{Float.round(overall * 100, 1)}%")
  IO.puts("  By benchmark: #{inspect(bench_scores)}")
  IO.puts("  Avg latency: #{Float.round(avg_lat / 1000, 2)}s | Avg tokens: #{round(avg_tok)}")
  IO.puts("  Errors: #{errors}")
  IO.puts("")
  %{adapter: to_string(adapter), overall_pct: Float.round(overall*100,1), bench_scores: bench_scores,
    avg_latency_s: Float.round(avg_lat/1000,2), avg_tokens: round(avg_tok), errors: errors}
end

File.mkdir_p!("bench_results")
output = %{run_id: "real_#{Date.utc_today()}", run_at: DateTime.utc_now() |> DateTime.to_iso8601(),
           summaries: summaries, raw: Enum.flat_map(results, fn {_,r} -> r end)}
File.write!("bench_results/real_run.json", Jason.encode!(output, pretty: true))
IO.puts("Saved to bench_results/real_run.json")
