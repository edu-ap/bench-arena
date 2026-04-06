defmodule BenchArena.TestHelpers do
  @moduledoc "Shared test helpers and fixtures."

  alias BenchArena.Corpus.Question
  alias BenchArena.Runner

  def sample_question(overrides \\ %{}) do
    defaults = %{
      id: "test_001",
      tier: 1,
      tier_name: "factual",
      prompt: "What is 2 + 2?",
      reference_answer: "4",
      scoring_method: :exact_match,
      rubric: nil,
      tags: [:math],
      expected_tokens_budget: 100
    }

    struct(Question, Map.merge(defaults, overrides))
  end

  def sample_run_result(overrides \\ %{}) do
    defaults = %{
      question_id: "test_001",
      tier: 1,
      adapter: :baseline,
      latency_ms: 5.0,
      tokens_in: 10,
      tokens_out: 5,
      total_tokens: 15,
      answer: "4",
      error: nil,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    struct(Runner, Map.merge(defaults, overrides))
  end

  def sample_semantic_question do
    sample_question(%{
      id: "test_sem_001",
      prompt: "What is the UCB1 formula?",
      reference_answer: "UCB1 = mean_reward + sqrt(2 * ln(N) / n_i)",
      scoring_method: :semantic
    })
  end

  def sample_rubric_question do
    sample_question(%{
      id: "test_rub_001",
      tier: 4,
      tier_name: "code",
      prompt: "Write a KL divergence function",
      reference_answer: "def kl_divergence(p, q) do ... end",
      scoring_method: :rubric,
      rubric: %{
        "criteria" => ["kl_divergence", "reduce", "log", "probability"],
        "max_score" => 4
      }
    })
  end
end
