defmodule BenchArena.RunnerTest do
  use ExUnit.Case, async: false

  alias BenchArena.Runner
  import BenchArena.TestHelpers

  describe "run_question/2 with baseline adapter" do
    test "returns a RunResult struct" do
      question = sample_question()
      result = Runner.run_question(question, :baseline)
      assert %Runner{} = result
    end

    test "sets question_id from question" do
      question = sample_question(%{id: "test_q42"})
      result = Runner.run_question(question, :baseline)
      assert result.question_id == "test_q42"
    end

    test "sets tier from question" do
      question = sample_question(%{tier: 3})
      result = Runner.run_question(question, :baseline)
      assert result.tier == 3
    end

    test "sets adapter name" do
      question = sample_question()
      result = Runner.run_question(question, :baseline)
      assert result.adapter == :baseline
    end

    test "records latency" do
      question = sample_question()
      result = Runner.run_question(question, :baseline)
      assert result.latency_ms > 0
    end

    test "records tokens" do
      question = sample_question()
      result = Runner.run_question(question, :baseline)
      assert result.tokens_in >= 0
      assert result.tokens_out >= 0
      assert result.total_tokens == result.tokens_in + result.tokens_out
    end

    test "returns an answer or credentials error for baseline" do
      question = sample_question(%{reference_answer: "42"})
      result = Runner.run_question(question, :baseline)
      # With API key: returns answer. Without: records error.
      assert is_binary(result.answer) or result.error == :credentials_not_configured
    end

    test "captures credentials error when PERPLEXITY_API_KEY not set" do
      original_env = System.get_env("PERPLEXITY_API_KEY")
      original_config = Application.get_env(:bench_arena, :perplexity_api_key)
      System.delete_env("PERPLEXITY_API_KEY")
      Application.put_env(:bench_arena, :perplexity_api_key, nil)

      try do
        question = sample_question()
        result = Runner.run_question(question, :baseline)
        assert result.error == :credentials_not_configured
      after
        if original_env, do: System.put_env("PERPLEXITY_API_KEY", original_env)
        if original_config, do: Application.put_env(:bench_arena, :perplexity_api_key, original_config)
      end
    end

    test "sets timestamp" do
      question = sample_question()
      result = Runner.run_question(question, :baseline)
      assert is_binary(result.timestamp)
    end

    test "raises for unknown adapter" do
      question = sample_question()
      assert_raise ArgumentError, ~r/Unknown adapter/, fn ->
        Runner.run_question(question, :nonexistent)
      end
    end
  end

  describe "run_comparison/1" do
    test "returns two results" do
      # This will fail with connection errors for agent_loop and stack,
      # but should still return results with errors captured
      question = sample_question()
      {agent_result, stack_result} = Runner.run_comparison(question)
      assert %Runner{} = agent_result
      assert %Runner{} = stack_result
      assert agent_result.adapter == :agent_loop
      assert stack_result.adapter == :stack
    end

    test "captures connection errors gracefully" do
      question = sample_question()
      {agent_result, stack_result} = Runner.run_comparison(question)
      # Both should have errors since services aren't running
      assert agent_result.error != nil
      assert stack_result.error != nil
    end
  end

  describe "run_all/2" do
    test "runs through all specified adapters" do
      question = sample_question()
      results = Runner.run_all(question, [:baseline])
      assert length(results) == 1
      assert hd(results).adapter == :baseline
    end

    test "returns results for each adapter" do
      question = sample_question()
      results = Runner.run_all(question, [:baseline, :baseline])
      assert length(results) == 2
    end
  end
end
