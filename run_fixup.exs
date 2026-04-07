
# run_fixup.exs — targeted re-run:
#   1. SimpleQA (15q) × [baseline, perplexity_standard, agent_loop, stack]
#   2. BBH remaining for stack (q5..q15 = 11q) — already has q1..q4
#   3. Tier 8 LegalLean (25q) × [baseline, perplexity_standard, agent_loop, stack]
# Merges with existing tier78_run.json, replacing broken scores.

Application.ensure_all_started(:bench_arena)
alias BenchArena.{Runner, Corpus, Scorer}

IO.puts("Loading corpus...")
tier7_all = Corpus.load_tier7()
tier8 = Corpus.load_tier8()

# Filter by benchmark_ref
tier7_simpleqa = Enum.filter(tier7_all, &(&1.benchmark_ref == "simpleqa"))
tier7_bbh = Enum.filter(tier7_all, &(&1.benchmark_ref == "bbh"))

IO.puts("SimpleQA: #{length(tier7_simpleqa)}q")
IO.puts("BBH: #{length(tier7_bbh)}q")
IO.puts("Tier 8: #{length(tier8)}q")

# Adapters for each phase
simpleqa_adapters = [:baseline, :perplexity_standard, :agent_loop, :stack]
bbh_stack_only = [:stack]
tier8_adapters = [:baseline, :perplexity_standard, :agent_loop, :stack]

# BBH questions that stack hasn't run yet (stack ran q1..q4 before timeout)
bbh_stack_remaining = Enum.filter(tier7_bbh, fn q ->
  q.id not in ["std_bbh_001", "std_bbh_002", "std_bbh_003", "std_bbh_004"]
end)
IO.puts("BBH stack remaining: #{length(bbh_stack_remaining)}q")

run_batch = fn questions, adapters, label ->
  IO.puts("\n=== #{label} ===")
  for adapter <- adapters do
    IO.puts("  --- #{adapter} ---")
    Enum.map(questions, fn q ->
      IO.write("    [#{q.id}] ")
      result = Runner.run_question(q, adapter)
      answer = result.answer || ""
      score = Scorer.score(answer, q)
      IO.puts("#{Float.round(result.latency_ms / 1000, 2)}s | score=#{Float.round(score, 2)} | #{String.slice(answer, 0, 60)}")
      %{
        adapter: to_string(adapter),
        question_id: q.id,
        benchmark_ref: q.benchmark_ref,
        tier: q.tier,
        score: score,
        latency_ms: result.latency_ms,
        total_tokens: result.total_tokens,
        error: if(result.error, do: inspect(result.error))
      }
    end)
  end
  |> List.flatten()
end

IO.puts("\n========================================")
IO.puts("PHASE 1: SimpleQA (15q × #{length(simpleqa_adapters)} adapters)")
IO.puts("========================================")
simpleqa_results = run_batch.(tier7_simpleqa, simpleqa_adapters, "SimpleQA")
IO.puts("Phase 1 done: #{length(simpleqa_results)} results")

IO.puts("\n========================================")
IO.puts("PHASE 2: BBH stack remaining (#{length(bbh_stack_remaining)}q)")
IO.puts("========================================")
bbh_remaining_results = run_batch.(bbh_stack_remaining, bbh_stack_only, "BBH stack remaining")
IO.puts("Phase 2 done: #{length(bbh_remaining_results)} results")

IO.puts("\n========================================")
IO.puts("PHASE 3: Tier 8 LegalLean (25q × #{length(tier8_adapters)} adapters)")
IO.puts("========================================")
tier8_results = run_batch.(tier8, tier8_adapters, "Tier 8 LegalLean")
IO.puts("Phase 3 done: #{length(tier8_results)} results")

# Load existing tier78_run.json and merge
existing = File.read!("bench_results/tier78_run.json") |> Jason.decode!()
old_raw = existing["raw"]

# New result keys that this run replaces: (adapter, question_id) pairs
new_keys =
  (simpleqa_results ++ bbh_remaining_results ++ tier8_results)
  |> Enum.map(fn r -> {r.adapter, r.question_id} end)
  |> MapSet.new()

# Keep old entries NOT replaced by new run
kept_old =
  Enum.filter(old_raw, fn r ->
    key = {r["adapter"], r["question_id"]}
    not MapSet.member?(new_keys, key)
  end)

IO.puts("\nKept #{length(kept_old)} old entries (non-replaced)")
IO.puts("New entries: #{length(simpleqa_results) + length(bbh_remaining_results) + length(tier8_results)}")

# Convert new results (atom-key maps) to string-key maps for consistency
stringify = fn map ->
  Map.new(map, fn {k, v} -> {to_string(k), v} end)
end

new_raw_str = Enum.map(
  simpleqa_results ++ bbh_remaining_results ++ tier8_results,
  stringify
)

merged_raw = kept_old ++ new_raw_str
IO.puts("Total merged: #{length(merged_raw)} entries")

output = %{
  "run_id" => "tier78_fixup_#{Date.utc_today()}",
  "run_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
  "raw" => merged_raw
}

File.write!("bench_results/tier78_run.json", Jason.encode!(output, pretty: true))
IO.puts("\nSaved merged results to bench_results/tier78_run.json")

# Print final summary
IO.puts("\n=== FINAL SUMMARY ===")
by_adapter_bench =
  Enum.group_by(merged_raw, fn r -> {r["adapter"], r["benchmark_ref"]} end)

adapters_ordered = ["baseline", "perplexity_standard", "agent_loop", "stack"]
benches_ordered = ["truthfulqa", "simpleqa", "bbh", "legallean"]

for adapter <- adapters_ordered do
  IO.puts("\n#{adapter}:")
  for bench <- benches_ordered do
    rows = Map.get(by_adapter_bench, {adapter, bench}, [])
    if rows != [] do
      scores = Enum.map(rows, fn r -> r["score"] || 0.0 end)
      avg = Enum.sum(scores) / length(scores) * 100
      IO.puts("  #{bench}: #{length(rows)}q, #{Float.round(avg, 1)}%")
    end
  end
end
