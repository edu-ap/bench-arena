Application.ensure_all_started(:bench_arena)
alias BenchArena.{Runner, Corpus, Scorer}

# All adapters that should now have real implementations
# stack is 3 API calls/question so skip for Tier 6 timing — use for Tier 1/2 sample
standard_adapters = [:baseline, :agent_loop, :perplexity_standard]
stack_adapters = [:stack]

# Load Tier 6 standard questions (25 total — industry benchmark aligned)
questions = Corpus.load_standard()
IO.puts("Standard questions: #{length(questions)}")

# Run stack on all 25 questions — 3 API calls each but sonar is fast
stack_sample = questions

all_results =
  for {adapters, qs} <- [{standard_adapters, questions}, {stack_adapters, stack_sample}],
      adapter <- adapters do
    IO.puts("\n=== #{adapter} (#{length(qs)} questions) ===")
    adapter_results = for q <- qs do
      IO.write("  [#{q.id}] ")
      result = Runner.run_question(q, adapter)
      answer = result.answer || ""
      score = Scorer.score(answer, q)
      status = if result.error, do: "ERR", else: "OK"
      IO.puts("#{Float.round(result.latency_ms/1000, 2)}s | #{result.total_tokens}tok | score=#{Float.round(score, 2)} | #{status}")
      %{
        adapter: to_string(adapter),
        question_id: q.id,
        benchmark_ref: q.benchmark_ref,
        latency_ms: result.latency_ms,
        total_tokens: result.total_tokens,
        score: score,
        error: if(result.error, do: inspect(result.error))
      }
    end
    {adapter, adapter_results}
  end

IO.puts("\n\n=== FINAL SUMMARY ===\n")
summaries = for {adapter, rows} <- all_results do
  ok = Enum.filter(rows, &is_nil(&1.error))
  overall = if ok == [], do: 0.0, else: Enum.sum(Enum.map(ok, & &1.score)) / length(ok)
  avg_lat = if ok == [], do: 0.0, else: Enum.sum(Enum.map(ok, & &1.latency_ms)) / length(ok)
  avg_tok = if ok == [], do: 0.0, else: Enum.sum(Enum.map(ok, & &1.total_tokens)) / length(ok)
  errors = length(rows) - length(ok)

  by_bench = Enum.group_by(ok, & &1.benchmark_ref)
  bench_scores = Map.new(by_bench, fn {b, qs} ->
    {b, Float.round(Enum.sum(Enum.map(qs, & &1.score)) / length(qs) * 100, 1)}
  end)

  IO.puts("#{adapter}:")
  IO.puts("  Overall: #{Float.round(overall*100,1)}% | #{Float.round(avg_lat/1000,2)}s | #{round(avg_tok)} tokens | #{errors} errors")
  IO.puts("  By benchmark: #{inspect(bench_scores)}")
  %{adapter: to_string(adapter), overall_pct: Float.round(overall*100,1),
    bench_scores: bench_scores, avg_latency_s: Float.round(avg_lat/1000,2),
    avg_tokens: round(avg_tok), errors: errors}
end

output = %{
  run_id: "all_real_#{Date.utc_today()}",
  run_at: DateTime.utc_now() |> DateTime.to_iso8601(),
  note: "Real API calls — no synthetic data. Stack run on 5-question sample due to 3x API cost.",
  summaries: summaries,
  raw: Enum.flat_map(all_results, fn {_, r} -> r end)
}
File.mkdir_p!("bench_results")
File.write!("bench_results/all_real_run.json", Jason.encode!(output, pretty: true))
IO.puts("\nSaved to bench_results/all_real_run.json")
