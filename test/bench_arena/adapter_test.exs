defmodule BenchArena.AdapterTest do
  use ExUnit.Case, async: true

  alias BenchArena.Adapters.BaselineAdapter
  import BenchArena.TestHelpers

  describe "BaselineAdapter.execute/1" do
    test "returns ok tuple" do
      question = sample_question()
      assert {:ok, result} = BaselineAdapter.execute(question)
      assert is_binary(result.answer)
    end

    test "returns token counts" do
      question = sample_question()
      {:ok, result} = BaselineAdapter.execute(question)
      assert result.tokens_in >= 0
      assert result.tokens_out >= 0
    end

    test "perturbs numeric answers" do
      question = sample_question(%{reference_answer: "42"})
      {:ok, result} = BaselineAdapter.execute(question)
      assert String.contains?(result.answer, "42")
    end

    test "returns short answers as-is" do
      question = sample_question(%{reference_answer: "POST"})
      {:ok, result} = BaselineAdapter.execute(question)
      assert result.answer == "POST"
    end

    test "truncates long answers" do
      long_answer = String.duplicate("word ", 100)
      question = sample_question(%{reference_answer: long_answer})
      {:ok, result} = BaselineAdapter.execute(question)
      assert String.length(result.answer) < String.length(long_answer)
    end

    test "handles nil reference_answer" do
      question = sample_question(%{reference_answer: nil})
      {:ok, result} = BaselineAdapter.execute(question)
      assert result.answer == "unknown"
    end

    test "tokens_out is at least 1" do
      question = sample_question(%{reference_answer: "x"})
      {:ok, result} = BaselineAdapter.execute(question)
      assert result.tokens_out >= 1
    end
  end

  describe "AgentLoopAdapter and StackAdapter error handling" do
    test "agent_loop returns error when service unavailable" do
      question = sample_question()
      result = BenchArena.Adapters.AgentLoopAdapter.execute(question)
      assert {:error, _reason} = result
    end

    test "stack returns error when service unavailable" do
      question = sample_question()
      result = BenchArena.Adapters.StackAdapter.execute(question)
      assert {:error, _reason} = result
    end
  end
end
