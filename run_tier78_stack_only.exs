Application.ensure_all_started(:bench_arena)
alias BenchArena.{Runner, Corpus, Scorer}

tier7 = Corpus.load_tier7()
tier8 = Corpus.load_tier8()
all_questions = tier7 ++ tier8

IO.puts("=== stack (#{length(all_questions)} questions) ===")
rows = for q <- all_questions do
  IO.write("  [#{q.id}] ")
  task = Task.async(fn -> Runner.run_question(q, :stack) end)
  case Task.yield(task, 30_000) || Task.shutdown(task) do
    {:ok, result} ->
      answer = result.answer || ""
      score = Scorer.score(answer, q)
      IO.puts("#{Float.round(result.latency_ms/1000,2)}s | score=#{Float.round(score,2)}")
      %{adapter: "stack", question_id: q.id,
        benchmark_ref: q.benchmark_ref, tier: q.tier,
        score: score, latency_ms: result.latency_ms,
        total_tokens: result.total_tokens,
        error: nil}
    _ ->
      IO.puts("TIMEOUT")
      %{adapter: "stack", question_id: q.id,
        benchmark_ref: q.benchmark_ref, tier: q.tier,
        score: 0.0, latency_ms: 30000.0,
        total_tokens: 0,
        error: "timeout"}
  end
end

ok = Enum.filter(rows, &is_nil(&1.error))
by_bench = Enum.group_by(ok, & &1.benchmark_ref)
IO.puts("\n=== STACK SUMMARY ===")
for {b, qs} <- Enum.sort(by_bench) do
  sc = Float.round(Enum.sum(Enum.map(qs, & &1.score)) / length(qs) * 100, 1)
  IO.puts("  #{b}: #{sc}%")
end
overall = if ok == [], do: 0.0, else: Enum.sum(Enum.map(ok, & &1.score)) / length(ok) * 100
IO.puts("  OVERALL: #{Float.round(overall,1)}%")
