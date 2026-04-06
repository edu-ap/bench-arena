defmodule BenchArena.MetricCollector do
  @moduledoc """
  ETS-backed metric store. All benchmark runs write their metrics here.
  Supports querying by tier, adapter, and run_id.
  """

  use GenServer

  @table :bench_arena_metrics

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Record a run result with optional accuracy score.
  Accepts a map with at minimum :question_id, :adapter, :latency_ms, :tokens_in, :tokens_out.
  """
  @spec record(map()) :: :ok
  def record(result) when is_map(result) do
    GenServer.call(__MODULE__, {:record, result})
  end

  @doc """
  Get summary statistics, optionally filtered by criteria.
  Returns a map keyed by adapter with stats: mean_latency_ms, p50, p99, mean_tokens, pass_rate.
  """
  @spec summary(map()) :: map()
  def summary(filters \\ %{}) do
    GenServer.call(__MODULE__, {:summary, filters})
  end

  @doc """
  Compute tradeoff deltas between stack and agent_loop.
  Returns latency_delta_ms, token_delta, accuracy_delta, and pi_score.
  """
  @spec tradeoff_report() :: map()
  def tradeoff_report do
    GenServer.call(__MODULE__, :tradeoff_report)
  end

  @doc """
  Clear all stored metrics.
  """
  @spec reset() :: :ok
  def reset do
    GenServer.call(__MODULE__, :reset)
  end

  @doc """
  Get summary statistics broken down by tier.
  Returns a map keyed by tier number with per-tier stats for each adapter.
  """
  @spec summary_by_tier(atom()) :: map()
  def summary_by_tier(adapter) do
    GenServer.call(__MODULE__, {:summary_by_tier, adapter})
  end

  @doc """
  Returns a map grouping adapters by category.
  """
  @spec adapter_groups() :: map()
  def adapter_groups do
    %{
      stack_internal: [:baseline, :agent_loop, :stack],
      perplexity: [:perplexity_standard, :perplexity_deep_research, :perplexity_model_council],
      external_ai: [:claude_code, :codex, :gemini_cli]
    }
  end

  @doc """
  Get all recorded results.
  """
  @spec all_results() :: [map()]
  def all_results do
    GenServer.call(__MODULE__, :all_results)
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    table = :ets.new(@table, [:bag, :named_table, :public])
    {:ok, %{table: table}}
  end

  @impl true
  def handle_call({:record, result}, _from, state) do
    entry = %{
      question_id: Map.get(result, :question_id),
      adapter: normalize_adapter(Map.get(result, :adapter)),
      tier: Map.get(result, :tier),
      latency_ms: Map.get(result, :latency_ms, 0.0),
      tokens_in: Map.get(result, :tokens_in, 0),
      tokens_out: Map.get(result, :tokens_out, 0),
      total_tokens: Map.get(result, :total_tokens, 0),
      accuracy: Map.get(result, :accuracy, 0.0),
      answer: Map.get(result, :answer),
      error: Map.get(result, :error),
      timestamp: Map.get(result, :timestamp)
    }

    :ets.insert(@table, {entry.adapter, entry})
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:summary, filters}, _from, state) do
    results = fetch_all()
    filtered = apply_filters(results, filters)
    grouped = Enum.group_by(filtered, & &1.adapter)

    summary =
      Map.new(grouped, fn {adapter, entries} ->
        latencies = Enum.map(entries, & &1.latency_ms)
        tokens = Enum.map(entries, & &1.total_tokens)
        accuracies = Enum.map(entries, & &1.accuracy)

        stats = %{
          count: length(entries),
          mean_latency_ms: safe_mean(latencies),
          p50: percentile(latencies, 50),
          p99: percentile(latencies, 99),
          mean_tokens: safe_mean(tokens),
          mean_accuracy: safe_mean(accuracies),
          pass_rate: pass_rate(accuracies)
        }

        {adapter, stats}
      end)

    {:reply, summary, state}
  end

  @impl true
  def handle_call(:tradeoff_report, _from, state) do
    results = fetch_all()
    grouped = Enum.group_by(results, & &1.adapter)

    agent_entries = Map.get(grouped, :agent_loop, [])
    stack_entries = Map.get(grouped, :stack, [])

    if agent_entries == [] or stack_entries == [] do
      {:reply, %{
        latency_delta_ms: 0.0,
        token_delta: 0.0,
        accuracy_delta: 0.0,
        pi_score: 0.0
      }, state}
    else
      agent_latency = safe_mean(Enum.map(agent_entries, & &1.latency_ms))
      stack_latency = safe_mean(Enum.map(stack_entries, & &1.latency_ms))
      agent_tokens = safe_mean(Enum.map(agent_entries, & &1.total_tokens))
      stack_tokens = safe_mean(Enum.map(stack_entries, & &1.total_tokens))
      agent_accuracy = safe_mean(Enum.map(agent_entries, & &1.accuracy))
      stack_accuracy = safe_mean(Enum.map(stack_entries, & &1.accuracy))

      latency_delta = stack_latency - agent_latency
      token_delta = stack_tokens - agent_tokens
      accuracy_delta = stack_accuracy - agent_accuracy

      pi_score = accuracy_delta - 0.001 * latency_delta - 0.0001 * token_delta

      {:reply, %{
        latency_delta_ms: Float.round(latency_delta, 2),
        token_delta: Float.round(token_delta, 2),
        accuracy_delta: Float.round(accuracy_delta, 4),
        pi_score: Float.round(pi_score, 4)
      }, state}
    end
  end

  @impl true
  def handle_call({:summary_by_tier, adapter}, _from, state) do
    results = fetch_all()

    filtered =
      if adapter do
        Enum.filter(results, &(&1.adapter == normalize_adapter(adapter)))
      else
        results
      end

    grouped = Enum.group_by(filtered, & &1.tier)

    by_tier =
      Map.new(grouped, fn {tier, entries} ->
        latencies = Enum.map(entries, & &1.latency_ms)
        tokens = Enum.map(entries, & &1.total_tokens)
        accuracies = Enum.map(entries, & &1.accuracy)

        stats = %{
          count: length(entries),
          mean_latency_ms: safe_mean(latencies),
          mean_tokens: safe_mean(tokens),
          mean_accuracy: safe_mean(accuracies),
          pass_rate: pass_rate(accuracies)
        }

        {tier, stats}
      end)

    {:reply, by_tier, state}
  end

  @impl true
  def handle_call(:reset, _from, state) do
    :ets.delete_all_objects(@table)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:all_results, _from, state) do
    {:reply, fetch_all(), state}
  end

  # Private helpers

  defp fetch_all do
    :ets.tab2list(@table)
    |> Enum.map(fn {_key, entry} -> entry end)
  end

  defp apply_filters(results, filters) when map_size(filters) == 0, do: results

  defp apply_filters(results, filters) do
    Enum.filter(results, fn entry ->
      Enum.all?(filters, fn
        {:tier, tier} -> entry.tier == tier
        {:adapter, adapter} -> entry.adapter == normalize_adapter(adapter)
        _ -> true
      end)
    end)
  end

  defp normalize_adapter(adapter) when is_atom(adapter), do: adapter
  defp normalize_adapter(adapter) when is_binary(adapter), do: String.to_atom(adapter)

  defp safe_mean([]), do: 0.0
  defp safe_mean(values), do: Enum.sum(values) / length(values)

  defp percentile([], _p), do: 0.0

  defp percentile(values, p) do
    sorted = Enum.sort(values)
    k = (p / 100.0) * (length(sorted) - 1)
    f = Float.floor(k)
    c = Float.ceil(k)

    if f == c do
      Enum.at(sorted, trunc(f))
    else
      lower = Enum.at(sorted, trunc(f))
      upper = Enum.at(sorted, trunc(c))
      lower + (upper - lower) * (k - f)
    end
  end

  defp pass_rate([]), do: 0.0

  defp pass_rate(accuracies) do
    passing = Enum.count(accuracies, &(&1 >= 0.5))
    passing / length(accuracies)
  end
end
