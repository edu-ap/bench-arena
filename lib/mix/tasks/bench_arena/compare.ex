defmodule Mix.Tasks.BenchArena.Compare do
  @moduledoc """
  Compare results from a benchmark run.

  ## Usage

      mix bench_arena.compare --run-id <id> [options]

  ## Options

    * `--run-id ID` - Compare results for a specific run (required)
    * `--tier N` - Filter by tier
  """

  use Mix.Task

  alias BenchArena.{Comparator, Runner}

  @shortdoc "Compare bench-arena run results"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} =
      OptionParser.parse(args,
        strict: [run_id: :string, tier: :integer]
      )

    run_id = Keyword.get(opts, :run_id)
    tier = Keyword.get(opts, :tier)

    unless run_id do
      Mix.raise("--run-id is required. Use `mix bench_arena.compare --run-id <id>`")
    end

    output_dir = Application.get_env(:bench_arena, :results_dir, "bench_results")
    json_path = Path.join(output_dir, "#{run_id}.json")

    unless File.exists?(json_path) do
      Mix.raise("Results file not found: #{json_path}")
    end

    data = json_path |> File.read!() |> Jason.decode!()
    results = data["results"]

    results =
      if tier do
        Enum.filter(results, &(&1["tier"] == tier))
      else
        results
      end

    grouped = Enum.group_by(results, & &1["question_id"])

    comparisons =
      Enum.flat_map(grouped, fn {_qid, group} ->
        agent = Enum.find(group, &(&1["adapter"] == "agent_loop"))
        stack = Enum.find(group, &(&1["adapter"] == "stack"))

        if agent && stack do
          a = to_run_result(agent)
          s = to_run_result(stack)
          [Comparator.compare(a, s)]
        else
          []
        end
      end)

    Mix.shell().info("BenchArena Comparison: #{run_id}")

    if tier do
      Mix.shell().info("Tier: #{tier}")
    end

    Mix.shell().info("---")

    # Tradeoff matrix header
    Mix.shell().info("\n| Question | Latency Winner | Token Winner | Accuracy Winner | Latency Δ | Token Δ | Accuracy Δ |")
    Mix.shell().info("|----------|---------------|-------------|-----------------|-----------|---------|------------|")

    Enum.each(comparisons, fn c ->
      Mix.shell().info(
        "| #{c.question_id} | #{c.latency_winner} | #{c.token_winner} | #{c.accuracy_winner} | #{c.latency_delta_ms}ms | #{c.token_delta} | #{c.accuracy_delta} |"
      )
    end)

    # Verdicts
    Mix.shell().info("\n--- Verdicts ---")

    Enum.each(comparisons, fn c ->
      {verdict, justification} = Comparator.verdict(c)
      Mix.shell().info("#{c.question_id}: #{verdict} — #{justification}")
    end)

    # Overall
    if comparisons != [] do
      stack_wins = Enum.count(comparisons, fn c -> match?({:stack_wins, _}, Comparator.verdict(c)) end)
      agent_wins = Enum.count(comparisons, fn c -> match?({:agent_wins, _}, Comparator.verdict(c)) end)
      ties = length(comparisons) - stack_wins - agent_wins

      Mix.shell().info("\n--- Overall ---")
      Mix.shell().info("Stack wins: #{stack_wins} | Agent wins: #{agent_wins} | Ties: #{ties}")
    end
  end

  defp to_run_result(map) do
    %Runner{
      question_id: map["question_id"],
      tier: map["tier"],
      adapter: String.to_atom(map["adapter"]),
      latency_ms: (map["latency_ms"] || 0) * 1.0,
      tokens_in: map["tokens_in"] || 0,
      tokens_out: map["tokens_out"] || 0,
      total_tokens: map["total_tokens"] || 0,
      answer: map["answer"],
      error: map["error"],
      timestamp: map["timestamp"]
    }
  end
end
