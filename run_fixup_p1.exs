
# Phase 1: Re-run SimpleQA (15q × 4 adapters) with fixed scorer
# Baseline + standard are fast; agent_loop + stack ~12s/q each = ~360s total

Application.ensure_all_started(:bench_arena)
alias BenchArena.{Runner, Corpus, Scorer}

tier7_all = Corpus.load_tier7()
tier7_simpleqa = Enum.filter(tier7_all, &(&1.benchmark_ref == "simpleqa"))
IO.puts("SimpleQA questions: #{length(tier7_simpleqa)}")

adapters = [:baseline, :perplexity_standard, :agent_loop, :stack]

new_results =
  for adapter <- adapters do
    IO.puts("\n  --- #{adapter} ---")
    Enum.map(tier7_simpleqa, fn q ->
      IO.write("    [#{q.id}] ")
      result = Runner.run_question(q, adapter)
      answer = result.answer || ""
      score = Scorer.score(answer, q)
      IO.puts("#{Float.round(result.latency_ms / 1000, 2)}s | #{Float.round(score, 2)} | ref=#{q.reference_answer} | ans=#{String.slice(answer, 0, 80)}")
      %{
        "adapter" => to_string(adapter),
        "question_id" => q.id,
        "benchmark_ref" => q.benchmark_ref,
        "tier" => q.tier,
        "score" => score,
        "latency_ms" => result.latency_ms,
        "total_tokens" => result.total_tokens,
        "error" => if(result.error, do: inspect(result.error))
      }
    end)
  end
  |> List.flatten()

IO.puts("\n\nPhase 1 complete: #{length(new_results)} results")

# Print summary
by_adapter = Enum.group_by(new_results, & &1["adapter"])
for adapter <- ["baseline", "perplexity_standard", "agent_loop", "stack"] do
  rows = Map.get(by_adapter, adapter, [])
  if rows != [] do
    scores = Enum.map(rows, & &1["score"])
    avg = Enum.sum(scores) / length(scores) * 100
    IO.puts("  #{adapter}: #{Float.round(avg, 1)}%  (#{length(rows)}q)")
  end
end

File.write!("bench_results/simpleqa_fixup.json", Jason.encode!(new_results, pretty: true))
IO.puts("\nSaved to bench_results/simpleqa_fixup.json")
