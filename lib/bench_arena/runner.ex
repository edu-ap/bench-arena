defmodule BenchArena.Runner do
  @moduledoc """
  Runs a benchmark question through both the agent loop and stack adapters,
  collecting latency, token usage, and raw answer for accuracy scoring.
  """

  defstruct [
    :question_id,
    :tier,
    :adapter,
    :latency_ms,
    :tokens_in,
    :tokens_out,
    :total_tokens,
    :answer,
    :error,
    :timestamp
  ]

  @type t :: %__MODULE__{
          question_id: String.t(),
          tier: integer(),
          adapter: atom(),
          latency_ms: float(),
          tokens_in: integer(),
          tokens_out: integer(),
          total_tokens: integer(),
          answer: String.t() | nil,
          error: term() | nil,
          timestamp: String.t()
        }

  alias BenchArena.Corpus.Question

  @adapter_modules %{
    baseline: BenchArena.Adapters.BaselineAdapter,
    agent_loop: BenchArena.Adapters.AgentLoopAdapter,
    stack: BenchArena.Adapters.StackAdapter,
    perplexity_standard: BenchArena.Adapters.PerplexityStandardAdapter,
    perplexity_deep_research: BenchArena.Adapters.PerplexityDeepResearchAdapter,
    perplexity_model_council: BenchArena.Adapters.PerplexityModelCouncilAdapter,
    claude_code: BenchArena.Adapters.ClaudeCodeAdapter,
    codex: BenchArena.Adapters.CodexAdapter,
    gemini_cli: BenchArena.Adapters.GeminiCliAdapter
  }

  @doc """
  Run a single question through the specified adapter, collecting metrics.
  """
  @spec run_question(Question.t(), atom()) :: t()
  def run_question(%Question{} = question, adapter) when is_atom(adapter) do
    adapter_mod = adapter_module(adapter)
    start_time = System.monotonic_time(:microsecond)

    {answer, tokens_in, tokens_out, error} =
      try do
        case adapter_mod.execute(question) do
          {:ok, %{answer: answer, tokens_in: tin, tokens_out: tout}} ->
            {answer, tin, tout, nil}

          {:error, reason} ->
            {nil, 0, 0, reason}
        end
      rescue
        e ->
          {nil, 0, 0, Exception.message(e)}
      end

    end_time = System.monotonic_time(:microsecond)
    latency_ms = (end_time - start_time) / 1_000

    :telemetry.execute(
      [:bench_arena, :run, :complete],
      %{latency_ms: latency_ms, tokens_in: tokens_in, tokens_out: tokens_out},
      %{adapter: adapter, tier: question.tier, question_id: question.id}
    )

    %__MODULE__{
      question_id: question.id,
      tier: question.tier,
      adapter: adapter,
      latency_ms: latency_ms,
      tokens_in: tokens_in,
      tokens_out: tokens_out,
      total_tokens: tokens_in + tokens_out,
      answer: answer,
      error: error,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  @doc """
  Run a question through both agent_loop and stack adapters sequentially
  for fair comparison.
  """
  @spec run_comparison(Question.t()) :: {t(), t()}
  def run_comparison(%Question{} = question) do
    agent_result = run_question(question, :agent_loop)
    stack_result = run_question(question, :stack)
    {agent_result, stack_result}
  end

  @doc """
  Run a question through all specified adapters.
  """
  @spec run_all(Question.t(), [atom()]) :: [t()]
  def run_all(
        %Question{} = question,
        adapters \\ [
          :baseline,
          :agent_loop,
          :stack,
          :perplexity_standard,
          :perplexity_deep_research,
          :perplexity_model_council,
          :claude_code,
          :codex,
          :gemini_cli
        ]
      ) do
    Enum.map(adapters, &run_question(question, &1))
  end

  defp adapter_module(adapter) do
    Map.get(@adapter_modules, adapter) ||
      raise ArgumentError, "Unknown adapter: #{inspect(adapter)}"
  end
end
