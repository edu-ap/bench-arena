defmodule BenchArena do
  @moduledoc """
  Top-level API for BenchArena — an Elixir benchmarking harness that measures
  agent loop vs stack performance across time, token usage, and accuracy.
  """

  alias BenchArena.{Runner, Corpus, MetricCollector, Comparator, Reporter, Scorer}

  @doc """
  Run a full benchmark comparison across all tiers.

  Options:
    - `:tier` - run only a specific tier (1-5), default: all
    - `:n` - sample N questions per tier, default: all
    - `:adapters` - list of adapters to test, default: [:agent_loop, :stack]
    - `:run_id` - custom run ID, default: auto-generated UUID
  """
  @spec run(keyword()) :: {:ok, String.t()} | {:error, term()}
  def run(opts \\ []) do
    run_id = Keyword.get(opts, :run_id, generate_run_id())
    tier = Keyword.get(opts, :tier)
    n = Keyword.get(opts, :n)
    adapters = Keyword.get(opts, :adapters, [:agent_loop, :stack])

    MetricCollector.reset()

    questions = load_questions(tier, n)

    results =
      Enum.flat_map(questions, fn question ->
        Enum.map(adapters, fn adapter ->
          result = Runner.run_question(question, adapter)
          scored = %{result | answer: result.answer}
          accuracy = Scorer.score(result.answer || "", question)
          final = %{scored | error: result.error}
          MetricCollector.record(Map.put(final, :accuracy, accuracy))
          {adapter, final, accuracy}
        end)
      end)

    output_dir = Application.get_env(:bench_arena, :results_dir, "bench_results")
    File.mkdir_p!(output_dir)

    results_data = Enum.map(results, fn {adapter, result, accuracy} ->
      %{
        question_id: result.question_id,
        tier: result.tier,
        adapter: adapter,
        latency_ms: result.latency_ms,
        tokens_in: result.tokens_in,
        tokens_out: result.tokens_out,
        total_tokens: result.total_tokens,
        answer: result.answer,
        accuracy: accuracy,
        error: if(result.error, do: inspect(result.error)),
        timestamp: result.timestamp
      }
    end)

    json_path = Path.join(output_dir, "#{run_id}.json")
    File.write!(json_path, Jason.encode!(%{run_id: run_id, results: results_data}, pretty: true))

    {:ok, run_id}
  end

  @doc """
  Compare results for two adapters, returning comparison structs.
  """
  @spec compare(String.t(), keyword()) :: [Comparator.t()]
  def compare(run_id, opts \\ []) do
    output_dir = Application.get_env(:bench_arena, :results_dir, "bench_results")
    json_path = Path.join(output_dir, "#{run_id}.json")

    case File.read(json_path) do
      {:ok, content} ->
        data = Jason.decode!(content)
        results = data["results"]

        tier_filter = Keyword.get(opts, :tier)

        results
        |> maybe_filter_tier(tier_filter)
        |> Enum.group_by(& &1["question_id"])
        |> Enum.flat_map(fn {_qid, group} ->
          agent = Enum.find(group, &(&1["adapter"] == "agent_loop"))
          stack = Enum.find(group, &(&1["adapter"] == "stack"))

          if agent && stack do
            [Comparator.compare(map_to_run_result(agent), map_to_run_result(stack))]
          else
            []
          end
        end)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Generate a report for a given run.
  """
  @spec report(String.t(), keyword()) :: {:ok, String.t()}
  def report(run_id, opts \\ []) do
    format = Keyword.get(opts, :format, :markdown)
    summary = MetricCollector.summary(%{})
    tradeoff = MetricCollector.tradeoff_report()
    Reporter.generate(run_id, summary, tradeoff, format: format)
  end

  defp load_questions(nil, nil), do: Corpus.all()
  defp load_questions(nil, n), do: Corpus.all() |> Enum.take(n)
  defp load_questions(tier, nil), do: Corpus.load_tier(tier)
  defp load_questions(tier, n), do: Corpus.sample(tier, n)

  defp generate_run_id do
    :crypto.strong_rand_bytes(8) |> Base.hex_encode32(case: :lower, padding: false) |> String.slice(0, 12)
  end

  defp maybe_filter_tier(results, nil), do: results
  defp maybe_filter_tier(results, tier), do: Enum.filter(results, &(&1["tier"] == tier))

  defp map_to_run_result(map) do
    %Runner{
      question_id: map["question_id"],
      tier: map["tier"],
      adapter: String.to_atom(map["adapter"]),
      latency_ms: map["latency_ms"],
      tokens_in: map["tokens_in"],
      tokens_out: map["tokens_out"],
      total_tokens: map["total_tokens"],
      answer: map["answer"],
      error: map["error"],
      timestamp: map["timestamp"]
    }
  end
end
