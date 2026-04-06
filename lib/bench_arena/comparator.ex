defmodule BenchArena.Comparator do
  @moduledoc """
  Takes two RunResults (one per adapter) and produces comparison analysis
  with per-dimension winners and an overall recommendation.
  """

  alias BenchArena.Runner

  defstruct [
    :question_id,
    :latency_winner,
    :token_winner,
    :accuracy_winner,
    :latency_delta_ms,
    :token_delta,
    :accuracy_delta,
    :recommendation
  ]

  @type t :: %__MODULE__{
          question_id: String.t(),
          latency_winner: :agent_loop | :stack | :tie,
          token_winner: :agent_loop | :stack | :tie,
          accuracy_winner: :agent_loop | :stack | :tie,
          latency_delta_ms: float(),
          token_delta: float(),
          accuracy_delta: float(),
          recommendation: String.t()
        }

  @latency_threshold 10.0
  @token_threshold 5
  @accuracy_threshold 0.05

  @doc """
  Compare two RunResults and produce a Comparison struct.
  First argument is agent_loop result, second is stack result.
  """
  @spec compare(Runner.t(), Runner.t()) :: t()
  def compare(%Runner{} = agent, %Runner{} = stack) do
    latency_delta = (stack.latency_ms || 0.0) - (agent.latency_ms || 0.0)
    token_delta = (stack.total_tokens || 0) - (agent.total_tokens || 0)

    agent_accuracy = compute_accuracy(agent)
    stack_accuracy = compute_accuracy(stack)
    accuracy_delta = stack_accuracy - agent_accuracy

    %__MODULE__{
      question_id: agent.question_id,
      latency_winner: winner(:lower, latency_delta, @latency_threshold),
      token_winner: winner(:lower, token_delta, @token_threshold),
      accuracy_winner: winner(:higher, accuracy_delta, @accuracy_threshold),
      latency_delta_ms: Float.round(latency_delta * 1.0, 2),
      token_delta: Float.round(token_delta * 1.0, 2),
      accuracy_delta: Float.round(accuracy_delta * 1.0, 4),
      recommendation: build_recommendation(latency_delta, token_delta, accuracy_delta)
    }
  end

  @doc """
  Given a list of Comparison structs, rank by each dimension.
  Returns a map with dimension keys and sorted lists.
  """
  @spec rank_tradeoffs([t()]) :: map()
  def rank_tradeoffs(comparisons) when is_list(comparisons) do
    %{
      by_latency: Enum.sort_by(comparisons, & &1.latency_delta_ms),
      by_tokens: Enum.sort_by(comparisons, & &1.token_delta),
      by_accuracy: Enum.sort_by(comparisons, & &1.accuracy_delta, :desc)
    }
  end

  @doc """
  Returns an overall verdict: :stack_wins, :agent_wins, or :tie with justification.
  """
  @spec verdict(t()) :: {atom(), String.t()}
  def verdict(%__MODULE__{} = comparison) do
    scores = %{
      stack: count_wins(comparison, :stack),
      agent_loop: count_wins(comparison, :agent_loop)
    }

    cond do
      scores.stack > scores.agent_loop ->
        {:stack_wins, "Stack wins #{scores.stack}/3 dimensions (latency, tokens, accuracy)"}

      scores.agent_loop > scores.stack ->
        {:agent_wins, "Agent loop wins #{scores.agent_loop}/3 dimensions"}

      true ->
        {:tie, "Tied at #{scores.stack}/3 dimensions each"}
    end
  end

  @doc """
  Returns a 3x2 tradeoff matrix: [{dimension, stack_value, agent_value, winner}].
  Requires the original RunResults to extract absolute values.
  """
  @spec tradeoff_matrix(t(), Runner.t(), Runner.t()) :: [map()]
  def tradeoff_matrix(%__MODULE__{} = comparison, %Runner{} = agent, %Runner{} = stack) do
    [
      %{
        dimension: :latency_ms,
        agent_value: agent.latency_ms || 0.0,
        stack_value: stack.latency_ms || 0.0,
        winner: comparison.latency_winner
      },
      %{
        dimension: :total_tokens,
        agent_value: agent.total_tokens || 0,
        stack_value: stack.total_tokens || 0,
        winner: comparison.token_winner
      },
      %{
        dimension: :accuracy,
        agent_value: compute_accuracy(agent),
        stack_value: compute_accuracy(stack),
        winner: comparison.accuracy_winner
      }
    ]
  end

  # Private helpers

  defp winner(:lower, delta, threshold) do
    cond do
      delta > threshold -> :agent_loop
      delta < -threshold -> :stack
      true -> :tie
    end
  end

  defp winner(:higher, delta, threshold) do
    cond do
      delta > threshold -> :stack
      delta < -threshold -> :agent_loop
      true -> :tie
    end
  end

  defp count_wins(comparison, adapter) do
    [:latency_winner, :token_winner, :accuracy_winner]
    |> Enum.count(&(Map.get(comparison, &1) == adapter))
  end

  defp compute_accuracy(%Runner{error: nil, answer: answer}) when is_binary(answer), do: 1.0
  defp compute_accuracy(%Runner{error: nil, answer: nil}), do: 0.0
  defp compute_accuracy(%Runner{error: _}), do: 0.0

  defp build_recommendation(latency_delta, token_delta, accuracy_delta) do
    pi_score = accuracy_delta - 0.001 * latency_delta - 0.0001 * token_delta

    cond do
      pi_score > 0.1 ->
        "Stack recommended: accuracy gain outweighs cost (π=#{Float.round(pi_score, 4)})"

      pi_score < -0.1 ->
        "Agent loop recommended: lower cost with acceptable accuracy (π=#{Float.round(pi_score, 4)})"

      true ->
        "No clear winner: similar tradeoff profile (π=#{Float.round(pi_score, 4)})"
    end
  end
end
