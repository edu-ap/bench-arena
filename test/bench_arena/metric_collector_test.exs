defmodule BenchArena.MetricCollectorTest do
  use ExUnit.Case, async: false

  alias BenchArena.MetricCollector

  import BenchArena.TestHelpers

  setup do
    # Ensure MetricCollector is running (may have crashed in a previous test)
    case GenServer.whereis(MetricCollector) do
      nil ->
        {:ok, _pid} = MetricCollector.start_link([])
        :ok

      _pid ->
        :ok
    end

    MetricCollector.reset()
    :ok
  end

  describe "record/1" do
    test "records a run result" do
      result = sample_run_result()
      assert :ok = MetricCollector.record(result)
    end

    test "records multiple results" do
      r1 = sample_run_result(%{question_id: "q1", adapter: :agent_loop})
      r2 = sample_run_result(%{question_id: "q2", adapter: :stack})
      assert :ok = MetricCollector.record(r1)
      assert :ok = MetricCollector.record(r2)
    end

    test "records result with accuracy field" do
      result = sample_run_result() |> Map.put(:accuracy, 0.95)
      assert :ok = MetricCollector.record(result)
    end

    test "records result with nil answer" do
      result = sample_run_result(%{answer: nil, error: "timeout"})
      assert :ok = MetricCollector.record(result)
    end

    test "records result with zero tokens" do
      result = sample_run_result(%{tokens_in: 0, tokens_out: 0, total_tokens: 0})
      assert :ok = MetricCollector.record(result)
    end
  end

  describe "summary/1" do
    test "returns empty map when no data" do
      assert MetricCollector.summary(%{}) == %{}
    end

    test "returns summary grouped by adapter" do
      MetricCollector.record(sample_run_result(%{adapter: :agent_loop, latency_ms: 100.0, total_tokens: 200}) |> Map.put(:accuracy, 0.8))
      MetricCollector.record(sample_run_result(%{adapter: :stack, latency_ms: 200.0, total_tokens: 300}) |> Map.put(:accuracy, 0.9))

      summary = MetricCollector.summary(%{})
      assert Map.has_key?(summary, :agent_loop)
      assert Map.has_key?(summary, :stack)
    end

    test "computes mean latency correctly" do
      MetricCollector.record(sample_run_result(%{adapter: :baseline, latency_ms: 10.0}) |> Map.put(:accuracy, 1.0))
      MetricCollector.record(sample_run_result(%{adapter: :baseline, latency_ms: 20.0, question_id: "q2"}) |> Map.put(:accuracy, 1.0))

      summary = MetricCollector.summary(%{})
      assert summary[:baseline].mean_latency_ms == 15.0
    end

    test "computes p50 correctly" do
      [5.0, 10.0, 15.0, 20.0, 25.0]
      |> Enum.with_index()
      |> Enum.each(fn {lat, i} ->
        MetricCollector.record(sample_run_result(%{adapter: :baseline, latency_ms: lat, question_id: "q#{i}"}) |> Map.put(:accuracy, 1.0))
      end)

      summary = MetricCollector.summary(%{})
      assert summary[:baseline].p50 == 15.0
    end

    test "computes p99 correctly" do
      [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 100.0]
      |> Enum.with_index()
      |> Enum.each(fn {lat, i} ->
        MetricCollector.record(sample_run_result(%{adapter: :baseline, latency_ms: lat, question_id: "q#{i}"}) |> Map.put(:accuracy, 1.0))
      end)

      summary = MetricCollector.summary(%{})
      assert summary[:baseline].p99 > 50.0
    end

    test "computes mean tokens correctly" do
      MetricCollector.record(sample_run_result(%{adapter: :baseline, total_tokens: 100}) |> Map.put(:accuracy, 1.0))
      MetricCollector.record(sample_run_result(%{adapter: :baseline, total_tokens: 200, question_id: "q2"}) |> Map.put(:accuracy, 1.0))

      summary = MetricCollector.summary(%{})
      assert summary[:baseline].mean_tokens == 150.0
    end

    test "computes pass rate correctly" do
      MetricCollector.record(sample_run_result(%{adapter: :baseline}) |> Map.put(:accuracy, 0.8))
      MetricCollector.record(sample_run_result(%{adapter: :baseline, question_id: "q2"}) |> Map.put(:accuracy, 0.3))

      summary = MetricCollector.summary(%{})
      assert summary[:baseline].pass_rate == 0.5
    end

    test "filters by tier" do
      MetricCollector.record(sample_run_result(%{adapter: :baseline, tier: 1}) |> Map.put(:accuracy, 1.0))
      MetricCollector.record(sample_run_result(%{adapter: :baseline, tier: 2, question_id: "q2"}) |> Map.put(:accuracy, 1.0))

      summary = MetricCollector.summary(%{tier: 1})
      assert summary[:baseline].count == 1
    end

    test "filters by adapter" do
      MetricCollector.record(sample_run_result(%{adapter: :agent_loop}) |> Map.put(:accuracy, 1.0))
      MetricCollector.record(sample_run_result(%{adapter: :stack, question_id: "q2"}) |> Map.put(:accuracy, 1.0))

      summary = MetricCollector.summary(%{adapter: :agent_loop})
      assert Map.has_key?(summary, :agent_loop)
      refute Map.has_key?(summary, :stack)
    end

    test "reports count of entries" do
      MetricCollector.record(sample_run_result(%{adapter: :baseline}) |> Map.put(:accuracy, 1.0))
      MetricCollector.record(sample_run_result(%{adapter: :baseline, question_id: "q2"}) |> Map.put(:accuracy, 1.0))
      MetricCollector.record(sample_run_result(%{adapter: :baseline, question_id: "q3"}) |> Map.put(:accuracy, 1.0))

      summary = MetricCollector.summary(%{})
      assert summary[:baseline].count == 3
    end

    test "computes mean accuracy" do
      MetricCollector.record(sample_run_result(%{adapter: :baseline}) |> Map.put(:accuracy, 0.6))
      MetricCollector.record(sample_run_result(%{adapter: :baseline, question_id: "q2"}) |> Map.put(:accuracy, 0.8))

      summary = MetricCollector.summary(%{})
      assert summary[:baseline].mean_accuracy == 0.7
    end
  end

  describe "tradeoff_report/0" do
    test "returns zeros when no data" do
      report = MetricCollector.tradeoff_report()
      assert report.latency_delta_ms == 0.0
      assert report.token_delta == 0.0
      assert report.accuracy_delta == 0.0
      assert report.pi_score == 0.0
    end

    test "computes latency delta (positive = stack slower)" do
      MetricCollector.record(sample_run_result(%{adapter: :agent_loop, latency_ms: 100.0}) |> Map.put(:accuracy, 0.5))
      MetricCollector.record(sample_run_result(%{adapter: :stack, latency_ms: 300.0, question_id: "q2"}) |> Map.put(:accuracy, 0.5))

      report = MetricCollector.tradeoff_report()
      assert report.latency_delta_ms == 200.0
    end

    test "computes token delta (positive = stack uses more)" do
      MetricCollector.record(sample_run_result(%{adapter: :agent_loop, total_tokens: 100}) |> Map.put(:accuracy, 0.5))
      MetricCollector.record(sample_run_result(%{adapter: :stack, total_tokens: 150, question_id: "q2"}) |> Map.put(:accuracy, 0.5))

      report = MetricCollector.tradeoff_report()
      assert report.token_delta == 50.0
    end

    test "computes accuracy delta (positive = stack more accurate)" do
      MetricCollector.record(sample_run_result(%{adapter: :agent_loop}) |> Map.put(:accuracy, 0.7))
      MetricCollector.record(sample_run_result(%{adapter: :stack, question_id: "q2"}) |> Map.put(:accuracy, 0.9))

      report = MetricCollector.tradeoff_report()
      assert report.accuracy_delta == 0.2
    end

    test "computes pi_score correctly" do
      MetricCollector.record(sample_run_result(%{adapter: :agent_loop, latency_ms: 100.0, total_tokens: 200}) |> Map.put(:accuracy, 0.7))
      MetricCollector.record(sample_run_result(%{adapter: :stack, latency_ms: 300.0, total_tokens: 250, question_id: "q2"}) |> Map.put(:accuracy, 0.9))

      report = MetricCollector.tradeoff_report()
      # pi = 0.2 - 0.001*200 - 0.0001*50 = 0.2 - 0.2 - 0.005 = -0.005
      assert report.pi_score == -0.005
    end

    test "handles only agent_loop data" do
      MetricCollector.record(sample_run_result(%{adapter: :agent_loop}) |> Map.put(:accuracy, 0.7))

      report = MetricCollector.tradeoff_report()
      assert report.latency_delta_ms == 0.0
    end

    test "handles only stack data" do
      MetricCollector.record(sample_run_result(%{adapter: :stack}) |> Map.put(:accuracy, 0.7))

      report = MetricCollector.tradeoff_report()
      assert report.latency_delta_ms == 0.0
    end
  end

  describe "reset/0" do
    test "clears all stored metrics" do
      MetricCollector.record(sample_run_result(%{adapter: :baseline}) |> Map.put(:accuracy, 1.0))
      assert MetricCollector.summary(%{}) != %{}

      MetricCollector.reset()
      assert MetricCollector.summary(%{}) == %{}
    end

    test "reset is idempotent" do
      MetricCollector.reset()
      MetricCollector.reset()
      assert MetricCollector.summary(%{}) == %{}
    end
  end

  describe "all_results/0" do
    test "returns empty list initially" do
      assert MetricCollector.all_results() == []
    end

    test "returns all recorded results" do
      MetricCollector.record(sample_run_result(%{question_id: "q1"}) |> Map.put(:accuracy, 1.0))
      MetricCollector.record(sample_run_result(%{question_id: "q2"}) |> Map.put(:accuracy, 0.5))

      results = MetricCollector.all_results()
      assert length(results) == 2
    end
  end
end
