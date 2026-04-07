Application.ensure_all_started(:bench_arena)
alias BenchArena.{Runner, Corpus, Scorer}

adapters = [:baseline, :perplexity_standard, :agent_loop, :stack]

tier7 = Corpus.load_tier7()
tier8 = Corpus.load_tier8()
all_questions = tier7 ++ tier8

IO.puts("Tier 7: #{length(tier7)} questions")
IO.puts("Tier 8: #{length(tier8)} questions")
IO.puts("Total: #{length(all_questions)} questions × #{length(adapters)} adapters")

results = for adapter <- adapters do
  IO.puts("\n=== #{adapter} ===")
  rows = for q <- all_questions do
    IO.write("  [#{q.id}] ")
    result = Runner.run_question(q, adapter)
    answer = result.answer || ""
    score = Scorer.score(answer, q)
    IO.puts("#{Float.round(result.latency_ms/1000,2)}s | score=#{Float.round(score,2)}")
    %{adapter: to_string(adapter), question_id: q.id,
      benchmark_ref: q.benchmark_ref, tier: q.tier,
      score: score, latency_ms: result.latency_ms,
      total_tokens: result.total_tokens,
      error: if(result.error, do: inspect(result.error))}
  end
  {adapter, rows}
end

# Print summary
IO.puts("\n\n=== SUMMARY ===\n")
for {adapter, rows} <- results do
  ok = Enum.filter(rows, &is_nil(&1.error))
  by_bench = Enum.group_by(ok, & &1.benchmark_ref)
  bench_scores = Map.new(by_bench, fn {b, qs} ->
    {b, Float.round(Enum.sum(Enum.map(qs, & &1.score)) / length(qs) * 100, 1)}
  end)
  overall = if ok == [], do: 0.0, else: Enum.sum(Enum.map(ok, & &1.score)) / length(ok) * 100
  IO.puts("#{adapter}: #{Float.round(overall,1)}% overall")
  for {b, sc} <- Enum.sort(bench_scores), do: IO.puts("  #{b}: #{sc}%")
end

File.mkdir_p!("bench_results")
output = %{run_id: "tier78_#{Date.utc_today()}", run_at: DateTime.utc_now() |> DateTime.to_iso8601(),
           raw: Enum.flat_map(results, fn {_,r} -> r end)}
File.write!("bench_results/tier78_run.json", Jason.encode!(output, pretty: true))
IO.puts("\nSaved to bench_results/tier78_run.json")
