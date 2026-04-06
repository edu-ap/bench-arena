defmodule BenchArena.ComparatorTest do
  use ExUnit.Case, async: true

  alias BenchArena.Comparator
  import BenchArena.TestHelpers

  describe "compare/2" do
    test "identifies latency winner when agent is faster" do
      agent = sample_run_result(%{adapter: :agent_loop, latency_ms: 50.0})
      stack = sample_run_result(%{adapter: :stack, latency_ms: 200.0})

      comparison = Comparator.compare(agent, stack)
      assert comparison.latency_winner == :agent_loop
      assert comparison.latency_delta_ms == 150.0
    end

    test "identifies latency winner when stack is faster" do
      agent = sample_run_result(%{adapter: :agent_loop, latency_ms: 200.0})
      stack = sample_run_result(%{adapter: :stack, latency_ms: 50.0})

      comparison = Comparator.compare(agent, stack)
      assert comparison.latency_winner == :stack
    end

    test "identifies latency tie when within threshold" do
      agent = sample_run_result(%{adapter: :agent_loop, latency_ms: 100.0})
      stack = sample_run_result(%{adapter: :stack, latency_ms: 105.0})

      comparison = Comparator.compare(agent, stack)
      assert comparison.latency_winner == :tie
    end

    test "identifies token winner when agent uses fewer" do
      agent = sample_run_result(%{adapter: :agent_loop, total_tokens: 100})
      stack = sample_run_result(%{adapter: :stack, total_tokens: 200})

      comparison = Comparator.compare(agent, stack)
      assert comparison.token_winner == :agent_loop
    end

    test "identifies token winner when stack uses fewer" do
      agent = sample_run_result(%{adapter: :agent_loop, total_tokens: 200})
      stack = sample_run_result(%{adapter: :stack, total_tokens: 100})

      comparison = Comparator.compare(agent, stack)
      assert comparison.token_winner == :stack
    end

    test "identifies token tie when within threshold" do
      agent = sample_run_result(%{adapter: :agent_loop, total_tokens: 100})
      stack = sample_run_result(%{adapter: :stack, total_tokens: 103})

      comparison = Comparator.compare(agent, stack)
      assert comparison.token_winner == :tie
    end

    test "identifies accuracy winner when stack has answer" do
      agent = sample_run_result(%{adapter: :agent_loop, answer: nil, error: "timeout"})
      stack = sample_run_result(%{adapter: :stack, answer: "4"})

      comparison = Comparator.compare(agent, stack)
      assert comparison.accuracy_winner == :stack
    end

    test "identifies accuracy tie when both have answers" do
      agent = sample_run_result(%{adapter: :agent_loop, answer: "4"})
      stack = sample_run_result(%{adapter: :stack, answer: "4"})

      comparison = Comparator.compare(agent, stack)
      assert comparison.accuracy_winner == :tie
    end

    test "computes deltas correctly" do
      agent = sample_run_result(%{adapter: :agent_loop, latency_ms: 100.0, total_tokens: 200, answer: "4"})
      stack = sample_run_result(%{adapter: :stack, latency_ms: 250.0, total_tokens: 300, answer: "4"})

      comparison = Comparator.compare(agent, stack)
      assert comparison.latency_delta_ms == 150.0
      assert comparison.token_delta == 100.0
    end

    test "sets question_id from agent result" do
      agent = sample_run_result(%{adapter: :agent_loop, question_id: "t1_005"})
      stack = sample_run_result(%{adapter: :stack})

      comparison = Comparator.compare(agent, stack)
      assert comparison.question_id == "t1_005"
    end

    test "generates recommendation string" do
      agent = sample_run_result(%{adapter: :agent_loop, latency_ms: 100.0})
      stack = sample_run_result(%{adapter: :stack, latency_ms: 200.0})

      comparison = Comparator.compare(agent, stack)
      assert is_binary(comparison.recommendation)
      assert String.length(comparison.recommendation) > 0
    end

    test "handles both errors" do
      agent = sample_run_result(%{adapter: :agent_loop, answer: nil, error: "fail"})
      stack = sample_run_result(%{adapter: :stack, answer: nil, error: "fail"})

      comparison = Comparator.compare(agent, stack)
      assert comparison.accuracy_winner == :tie
    end
  end

  describe "verdict/1" do
    test "returns :stack_wins when stack wins majority" do
      agent = sample_run_result(%{adapter: :agent_loop, latency_ms: 200.0, total_tokens: 300, answer: nil, error: "fail"})
      stack = sample_run_result(%{adapter: :stack, latency_ms: 50.0, total_tokens: 100, answer: "4"})

      comparison = Comparator.compare(agent, stack)
      {verdict, justification} = Comparator.verdict(comparison)
      assert verdict == :stack_wins
      assert String.contains?(justification, "Stack")
    end

    test "returns :agent_wins when agent wins majority" do
      agent = sample_run_result(%{adapter: :agent_loop, latency_ms: 50.0, total_tokens: 100, answer: "4"})
      stack = sample_run_result(%{adapter: :stack, latency_ms: 200.0, total_tokens: 300, answer: nil, error: "fail"})

      comparison = Comparator.compare(agent, stack)
      {verdict, justification} = Comparator.verdict(comparison)
      assert verdict == :agent_wins
      assert String.contains?(justification, "Agent")
    end

    test "returns :tie when dimensions are split" do
      agent = sample_run_result(%{adapter: :agent_loop, latency_ms: 50.0, total_tokens: 300, answer: "4"})
      stack = sample_run_result(%{adapter: :stack, latency_ms: 200.0, total_tokens: 100, answer: "4"})

      comparison = Comparator.compare(agent, stack)
      {verdict, _justification} = Comparator.verdict(comparison)
      assert verdict in [:tie, :agent_wins, :stack_wins]
    end
  end

  describe "rank_tradeoffs/1" do
    test "sorts by latency delta" do
      c1 = %Comparator{question_id: "q1", latency_delta_ms: 100.0, token_delta: 0.0, accuracy_delta: 0.0,
                        latency_winner: :agent_loop, token_winner: :tie, accuracy_winner: :tie, recommendation: ""}
      c2 = %Comparator{question_id: "q2", latency_delta_ms: 50.0, token_delta: 0.0, accuracy_delta: 0.0,
                        latency_winner: :tie, token_winner: :tie, accuracy_winner: :tie, recommendation: ""}

      ranked = Comparator.rank_tradeoffs([c1, c2])
      assert hd(ranked.by_latency).question_id == "q2"
    end

    test "sorts by accuracy delta descending" do
      c1 = %Comparator{question_id: "q1", latency_delta_ms: 0.0, token_delta: 0.0, accuracy_delta: 0.1,
                        latency_winner: :tie, token_winner: :tie, accuracy_winner: :stack, recommendation: ""}
      c2 = %Comparator{question_id: "q2", latency_delta_ms: 0.0, token_delta: 0.0, accuracy_delta: 0.5,
                        latency_winner: :tie, token_winner: :tie, accuracy_winner: :stack, recommendation: ""}

      ranked = Comparator.rank_tradeoffs([c1, c2])
      assert hd(ranked.by_accuracy).question_id == "q2"
    end

    test "handles empty list" do
      ranked = Comparator.rank_tradeoffs([])
      assert ranked.by_latency == []
      assert ranked.by_tokens == []
      assert ranked.by_accuracy == []
    end
  end

  describe "tradeoff_matrix/3" do
    test "returns three dimension rows" do
      agent = sample_run_result(%{adapter: :agent_loop, latency_ms: 100.0, total_tokens: 200, answer: "4"})
      stack = sample_run_result(%{adapter: :stack, latency_ms: 200.0, total_tokens: 300, answer: "4"})
      comparison = Comparator.compare(agent, stack)

      matrix = Comparator.tradeoff_matrix(comparison, agent, stack)
      assert length(matrix) == 3
      dimensions = Enum.map(matrix, & &1.dimension)
      assert :latency_ms in dimensions
      assert :total_tokens in dimensions
      assert :accuracy in dimensions
    end

    test "includes correct values" do
      agent = sample_run_result(%{adapter: :agent_loop, latency_ms: 100.0, total_tokens: 200, answer: "4"})
      stack = sample_run_result(%{adapter: :stack, latency_ms: 200.0, total_tokens: 300, answer: "4"})
      comparison = Comparator.compare(agent, stack)

      matrix = Comparator.tradeoff_matrix(comparison, agent, stack)
      latency_row = Enum.find(matrix, &(&1.dimension == :latency_ms))
      assert latency_row.agent_value == 100.0
      assert latency_row.stack_value == 200.0
    end
  end
end
