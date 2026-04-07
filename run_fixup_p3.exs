
# Phase 3: Tier 8 agent_loop (25q × ~12s = ~300s)

Application.ensure_all_started(:bench_arena)
alias BenchArena.{Runner, Corpus, Scorer}

tier8 = Corpus.load_tier8()
IO.puts("Tier 8: #{length(tier8)}q × agent_loop")

t8_agent =
  Enum.map(tier8, fn q ->
    IO.write("  [#{q.id}] ")
    result = Runner.run_question(q, :agent_loop)
    answer = result.answer || ""
    score = Scorer.score(answer, q)
    IO.puts("#{Float.round(result.latency_ms / 1000, 2)}s | #{Float.round(score, 2)}")
    %{
      "adapter" => "agent_loop",
      "question_id" => q.id,
      "benchmark_ref" => q.benchmark_ref,
      "tier" => q.tier,
      "score" => score,
      "latency_ms" => result.latency_ms,
      "total_tokens" => result.total_tokens,
      "error" => if(result.error, do: inspect(result.error))
    }
  end)

IO.puts("\nTier 8 agent_loop done: #{length(t8_agent)} results")
scores = Enum.map(t8_agent, & &1["score"])
avg = Enum.sum(scores) / length(scores) * 100
IO.puts("Average: #{Float.round(avg, 1)}%")

File.write!("bench_results/fixup_p3.json", Jason.encode!(t8_agent, pretty: true))
IO.puts("Saved to bench_results/fixup_p3.json")
