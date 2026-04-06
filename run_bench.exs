Application.ensure_all_started(:bench_arena)

alias BenchArena.{Runner, Corpus, MetricCollector, Reporter, Scorer}

MetricCollector.reset()

questions = Corpus.all()
IO.puts("Loaded #{length(questions)} questions across #{questions |> Enum.map(& &1.tier) |> Enum.uniq() |> length()} tiers")

results = Enum.map(questions, fn q ->
  result = Runner.run_question(q, :baseline)
  answer = case result.answer do
    nil -> ""
    a -> a
  end
  score = Scorer.score(answer, q)
  IO.puts("[tier#{q.tier}/#{q.id}] #{Float.round(result.latency_ms, 1)}ms #{result.total_tokens}tok score=#{Float.round(score, 2)}")
  {result, score}
end)

# Record all results
Enum.each(results, fn {r, score} ->
  MetricCollector.record(Map.from_struct(r) |> Map.put(:accuracy, score))
end)

summary = MetricCollector.summary(%{})
IO.puts("\n=== SUMMARY ===")
IO.inspect(summary, pretty: true)

# Generate markdown report
File.mkdir_p!("bench_results")
report_data = Enum.map(results, fn {r, score} ->
  %{
    question_id: r.question_id,
    tier: r.tier,
    adapter: Atom.to_string(r.adapter),
    latency_ms: r.latency_ms,
    tokens_in: r.tokens_in,
    tokens_out: r.tokens_out,
    total_tokens: r.total_tokens,
    answer: r.answer,
    accuracy: score,
    error: if(r.error, do: inspect(r.error)),
    timestamp: r.timestamp
  }
end)

run_id = "baseline_#{Date.utc_today() |> Date.to_iso8601()}"
json_path = "bench_results/#{run_id}.json"
File.write!(json_path, Jason.encode!(%{run_id: run_id, results: report_data}, pretty: true))
IO.puts("\nResults written to #{json_path}")

# Generate markdown report
tradeoff = MetricCollector.tradeoff_report()
{:ok, md} = BenchArena.Reporter.generate(run_id, summary, tradeoff, format: :markdown)
File.write!("bench_results/baseline_run.md", md)
IO.puts("Report written to bench_results/baseline_run.md")
