defmodule Mix.Tasks.BenchArena.Report do
  @moduledoc """
  Generate a benchmark report.

  ## Usage

      mix bench_arena.report --run-id <id> [options]

  ## Options

    * `--run-id ID` - Generate report for a specific run (required)
    * `--format FORMAT` - markdown or html, default: markdown
    * `--output FILE` - Write report to file
  """

  use Mix.Task

  alias BenchArena.{MetricCollector, Reporter, Runner}

  @shortdoc "Generate bench-arena benchmark report"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} =
      OptionParser.parse(args,
        strict: [run_id: :string, format: :string, output: :string]
      )

    run_id = Keyword.get(opts, :run_id)
    format = Keyword.get(opts, :format, "markdown") |> String.to_atom()
    output = Keyword.get(opts, :output)

    unless run_id do
      Mix.raise("--run-id is required. Use `mix bench_arena.report --run-id <id>`")
    end

    output_dir = Application.get_env(:bench_arena, :results_dir, "bench_results")
    json_path = Path.join(output_dir, "#{run_id}.json")

    unless File.exists?(json_path) do
      Mix.raise("Results file not found: #{json_path}")
    end

    # Load results into MetricCollector
    data = json_path |> File.read!() |> Jason.decode!()
    MetricCollector.reset()

    Enum.each(data["results"], fn r ->
      MetricCollector.record(%Runner{
        question_id: r["question_id"],
        tier: r["tier"],
        adapter: String.to_atom(r["adapter"]),
        latency_ms: (r["latency_ms"] || 0) * 1.0,
        tokens_in: r["tokens_in"] || 0,
        tokens_out: r["tokens_out"] || 0,
        total_tokens: r["total_tokens"] || 0,
        answer: r["answer"],
        error: r["error"],
        timestamp: r["timestamp"]
      } |> Map.put(:accuracy, r["accuracy"] || 0.0))
    end)

    summary = MetricCollector.summary(%{})
    tradeoff = MetricCollector.tradeoff_report()

    {:ok, content} = Reporter.generate(run_id, summary, tradeoff, format: format, output: output)

    if output do
      Mix.shell().info("Report written to #{output}")
    else
      Mix.shell().info(content)
    end
  end
end
