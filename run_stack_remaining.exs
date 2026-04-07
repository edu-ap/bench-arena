Application.ensure_all_started(:bench_arena)
alias BenchArena.{Runner, Corpus, Scorer}

questions = Corpus.load_standard()
# Stack was cut off at std_humaneval_002 onward — run humaneval 002-005, ifeval, aime
remaining = Enum.filter(questions, fn q ->
  q.id in ~w[std_humaneval_002 std_humaneval_003 std_humaneval_004 std_humaneval_005
             std_ifeval_001 std_ifeval_002 std_ifeval_003 std_ifeval_004 std_ifeval_005
             std_aime_001 std_aime_002 std_aime_003 std_aime_004 std_aime_005]
end)

IO.puts("Running #{length(remaining)} remaining stack questions")
results = for q <- remaining do
  IO.write("  [#{q.id}] ")
  result = Runner.run_question(q, :stack)
  answer = result.answer || ""
  score = Scorer.score(answer, q)
  status = if result.error, do: "ERR(#{inspect(result.error)})", else: "OK"
  IO.puts("#{Float.round(result.latency_ms/1000, 2)}s | #{result.total_tokens}tok | score=#{Float.round(score,2)} | #{status}")
  %{
    adapter: "stack", question_id: q.id, benchmark_ref: q.benchmark_ref,
    latency_ms: result.latency_ms, total_tokens: result.total_tokens,
    score: score, error: if(result.error, do: inspect(result.error))
  }
end

# Merge with existing results
existing = File.read!("bench_results/all_real_run.json") |> Jason.decode!()
existing_raw = existing["raw"]
# Remove any old stack entries for these questions
qids = Enum.map(remaining, & &1.id) |> MapSet.new()
filtered = Enum.reject(existing_raw, fn r -> r["adapter"] == "stack" and r["question_id"] in qids end)
merged = filtered ++ results

by_bench = Enum.group_by(
  Enum.filter(merged, fn r -> r["adapter"] == "stack" and is_nil(r["error"]) end),
  & &1["benchmark_ref"]
)
bench_scores = Map.new(by_bench, fn {b, qs} ->
  mean = Enum.sum(Enum.map(qs, & &1["score"])) / length(qs)
  {b, Float.round(mean * 100, 1)}
end)
IO.puts("\nStack full results: #{inspect(bench_scores)}")

# Rebuild summaries
updated = Map.put(existing, "raw", merged)
File.write!("bench_results/all_real_run.json", Jason.encode!(updated, pretty: true))
IO.puts("Saved updated results")
