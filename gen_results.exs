Application.ensure_all_started(:bench_arena)
alias BenchArena.Corpus

tier7 = Corpus.load_tier7()
tier8 = Corpus.load_tier8()
all_questions = tier7 ++ tier8

# Parse the output file for scores
parse_line = fn line ->
  case Regex.run(~r/\[(.+?)\]\s+[\d.]+s\s+\|\s+score=([\d.]+)/, line) do
    [_, id, score] -> {id, String.to_float(score)}
    _ -> nil
  end
end

parse_adapter = fn text, adapter_name ->
  text
  |> String.split("\n")
  |> Enum.map(parse_line)
  |> Enum.reject(&is_nil/1)
  |> Enum.map(fn {id, score} ->
    q = Enum.find(all_questions, &(&1.id == id))
    if q do
      %{adapter: adapter_name, question_id: id,
        benchmark_ref: q.benchmark_ref, tier: q.tier,
        score: score, latency_ms: 0.0, total_tokens: 0, error: nil}
    end
  end)
  |> Enum.reject(&is_nil/1)
end

# Read both output files
main_text = File.read!("/home/user/workspace/bench-arena-tier78-output.txt")
stack_text = File.read!("/home/user/workspace/bench-arena-stack-output.txt")

# Split main text by adapter sections
sections = Regex.split(~r/=== (\w+) ===/, main_text, include_captures: true)

# Parse each adapter
results = []
results = results ++ parse_adapter.(main_text |> String.split("=== baseline ===") |> List.last() |> String.split("=== perplexity_standard ===") |> List.first(), "baseline")
results = results ++ parse_adapter.(main_text |> String.split("=== perplexity_standard ===") |> List.last() |> String.split("=== agent_loop ===") |> List.first(), "perplexity_standard")
results = results ++ parse_adapter.(main_text |> String.split("=== agent_loop ===") |> List.last(), "agent_loop")
results = results ++ parse_adapter.(stack_text, "stack")

output = %{
  run_id: "tier78_2026-04-07",
  run_at: DateTime.utc_now() |> DateTime.to_iso8601(),
  raw: results
}

File.write!("bench_results/tier78_run.json", Jason.encode!(output, pretty: true))
IO.puts("Saved #{length(results)} results to bench_results/tier78_run.json")

# Print summary
for adapter <- ["baseline", "perplexity_standard", "agent_loop", "stack"] do
  rows = Enum.filter(results, &(&1.adapter == adapter))
  by_bench = Enum.group_by(rows, & &1.benchmark_ref)
  IO.puts("\n#{adapter}:")
  for {b, qs} <- Enum.sort(by_bench) do
    sc = Float.round(Enum.sum(Enum.map(qs, & &1.score)) / length(qs) * 100, 1)
    IO.puts("  #{b}: #{sc}% (#{length(qs)} q)")
  end
  overall = if rows == [], do: 0.0, else: Enum.sum(Enum.map(rows, & &1.score)) / length(rows) * 100
  IO.puts("  OVERALL: #{Float.round(overall,1)}%")
end
