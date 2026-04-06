defmodule Mix.Tasks.BenchArena.Run do
  @moduledoc """
  Run benchmark questions through adapters.

  ## Usage

      mix bench_arena.run [options]

  ## Options

    * `--tier N` - Run only tier N questions (1-5), default: all
    * `--n N` - Sample N questions per tier, default: all
    * `--adapter A` - agent_loop|stack|baseline|all, default: all
    * `--run-id ID` - Custom run ID, default: auto-generated UUID
    * `--output DIR` - Write results JSON to DIR, default: bench_results/
  """

  use Mix.Task

  alias BenchArena.{Runner, Corpus, MetricCollector, Scorer}

  @shortdoc "Run bench-arena benchmark questions"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} =
      OptionParser.parse(args,
        strict: [tier: :integer, n: :integer, adapter: :string, run_id: :string, output: :string]
      )

    tier = Keyword.get(opts, :tier)
    n = Keyword.get(opts, :n)
    adapter_opt = Keyword.get(opts, :adapter, "all")
    run_id = Keyword.get(opts, :run_id, generate_run_id())
    output_dir = Keyword.get(opts, :output, Application.get_env(:bench_arena, :results_dir, "bench_results"))

    adapters = parse_adapters(adapter_opt)
    questions = load_questions(tier, n)

    Mix.shell().info("BenchArena Run: #{run_id}")
    Mix.shell().info("Questions: #{length(questions)} | Adapters: #{inspect(adapters)}")
    Mix.shell().info("---")

    MetricCollector.reset()

    results =
      questions
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {question, idx} ->
        Enum.map(adapters, fn adapter ->
          result = Runner.run_question(question, adapter)
          accuracy = Scorer.score(result.answer || "", question)
          MetricCollector.record(Map.put(result, :accuracy, accuracy))

          status = if result.error, do: "✗", else: "✓"
          Mix.shell().info(
            "[tier#{question.tier}/q#{idx}] #{adapter}: #{Float.round(result.latency_ms, 1)}ms #{result.total_tokens}tok #{status}"
          )

          %{result: result, accuracy: accuracy, adapter: adapter}
        end)
      end)

    # Write results
    File.mkdir_p!(output_dir)
    results_data = Enum.map(results, fn %{result: r, accuracy: acc, adapter: adapter} ->
      %{
        question_id: r.question_id,
        tier: r.tier,
        adapter: Atom.to_string(adapter),
        latency_ms: r.latency_ms,
        tokens_in: r.tokens_in,
        tokens_out: r.tokens_out,
        total_tokens: r.total_tokens,
        answer: r.answer,
        accuracy: acc,
        error: if(r.error, do: inspect(r.error)),
        timestamp: r.timestamp
      }
    end)

    json_path = Path.join(output_dir, "#{run_id}.json")
    File.write!(json_path, Jason.encode!(%{run_id: run_id, results: results_data}, pretty: true))

    # Print summary
    Mix.shell().info("\n--- Summary ---")
    summary = MetricCollector.summary(%{})

    Enum.each(summary, fn {adapter, stats} ->
      Mix.shell().info(
        "#{adapter}: latency=#{Float.round(stats.mean_latency_ms, 1)}ms tokens=#{Float.round(stats.mean_tokens, 1)} accuracy=#{Float.round(stats.mean_accuracy, 4)} pass_rate=#{Float.round(stats.pass_rate, 4)}"
      )
    end)

    Mix.shell().info("\nResults written to #{json_path}")
  end

  defp load_questions(nil, nil), do: Corpus.all()
  defp load_questions(nil, n), do: Corpus.all() |> Enum.take(n)
  defp load_questions(tier, nil), do: Corpus.load_tier(tier)
  defp load_questions(tier, n), do: Corpus.sample(tier, n)

  defp parse_adapters("all"), do: [:agent_loop, :stack, :baseline]
  defp parse_adapters("agent_loop"), do: [:agent_loop]
  defp parse_adapters("stack"), do: [:stack]
  defp parse_adapters("baseline"), do: [:baseline]
  defp parse_adapters(_), do: [:agent_loop, :stack]

  defp generate_run_id do
    :crypto.strong_rand_bytes(8) |> Base.hex_encode32(case: :lower, padding: false) |> String.slice(0, 12)
  end
end
