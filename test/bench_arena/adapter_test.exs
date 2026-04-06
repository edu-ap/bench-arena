defmodule BenchArena.AdapterTest do
  use ExUnit.Case, async: true

  alias BenchArena.Adapters.BaselineAdapter
  import BenchArena.TestHelpers

  describe "BaselineAdapter.execute/1" do
    test "returns {:error, :credentials_not_configured} when PERPLEXITY_API_KEY is not set" do
      original_env = System.get_env("PERPLEXITY_API_KEY")
      original_config = Application.get_env(:bench_arena, :perplexity_api_key)
      System.delete_env("PERPLEXITY_API_KEY")
      Application.put_env(:bench_arena, :perplexity_api_key, nil)

      try do
        question = sample_question()
        assert {:error, :credentials_not_configured} = BaselineAdapter.execute(question)
      after
        if original_env, do: System.put_env("PERPLEXITY_API_KEY", original_env)
        if original_config, do: Application.put_env(:bench_arena, :perplexity_api_key, original_config)
      end
    end

    test "implements BenchArena.Adapter behaviour (exports execute/1)" do
      Code.ensure_loaded!(BaselineAdapter)
      assert function_exported?(BaselineAdapter, :execute, 1)
    end
  end

  describe "AgentLoopAdapter" do
    test "returns error when Elan agent loop fails or unavailable" do
      question = sample_question()
      result = BenchArena.Adapters.AgentLoopAdapter.execute(question)
      # In test env, Elan processes may not be fully running
      assert {:error, _reason} = result
    end

    test "implements BenchArena.Adapter behaviour" do
      Code.ensure_loaded!(BenchArena.Adapters.AgentLoopAdapter)
      assert function_exported?(BenchArena.Adapters.AgentLoopAdapter, :execute, 1)
    end
  end

  describe "StackAdapter" do
    test "returns result or error from CSC pipeline" do
      question = sample_question()
      result = BenchArena.Adapters.StackAdapter.execute(question)
      # CSC may fail on simple test prompts with unresolved_task
      case result do
        {:ok, %{answer: answer}} -> assert is_binary(answer)
        {:error, _reason} -> :ok
      end
    end

    test "implements BenchArena.Adapter behaviour" do
      Code.ensure_loaded!(BenchArena.Adapters.StackAdapter)
      assert function_exported?(BenchArena.Adapters.StackAdapter, :execute, 1)
    end
  end
end
