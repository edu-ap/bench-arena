defmodule BenchArena.Telemetry do
  @moduledoc """
  Telemetry integration for BenchArena. Attaches handlers that log
  benchmark events for observability.

  ## Events

  - `[:bench_arena, :run, :complete]` — emitted after each question run
    - Measurements: `%{latency_ms, tokens_in, tokens_out}`
    - Metadata: `%{adapter, tier, question_id}`

  - `[:bench_arena, :comparison, :complete]` — emitted after a comparison
    - Measurements: `%{latency_delta_ms, token_delta, accuracy_delta}`
    - Metadata: `%{question_id}`

  ## Usage

      BenchArena.Telemetry.attach()
  """

  require Logger

  @events [
    [:bench_arena, :run, :complete],
    [:bench_arena, :comparison, :complete],
    [:bench_arena, :groundtrace, :emitted]
  ]

  @doc """
  Attach telemetry handlers for all BenchArena events.
  """
  @spec attach() :: :ok
  def attach do
    :telemetry.attach_many(
      "bench-arena-logger",
      @events,
      &handle_event/4,
      nil
    )
  end

  @doc """
  Detach telemetry handlers.
  """
  @spec detach() :: :ok | {:error, :not_found}
  def detach do
    :telemetry.detach("bench-arena-logger")
  end

  @doc """
  List all registered event names.
  """
  @spec events() :: [list()]
  def events, do: @events

  @doc false
  def handle_event([:bench_arena, :run, :complete], measurements, metadata, _config) do
    Logger.info(
      "[BenchArena] #{metadata.adapter}/#{metadata.question_id}: " <>
        "#{Float.round(measurements.latency_ms, 1)}ms " <>
        "#{measurements.tokens_in}+#{measurements.tokens_out} tokens"
    )
  end

  def handle_event([:bench_arena, :comparison, :complete], measurements, metadata, _config) do
    Logger.info(
      "[BenchArena] Comparison #{metadata.question_id}: " <>
        "latency_delta=#{Float.round(measurements.latency_delta_ms, 1)}ms " <>
        "token_delta=#{measurements.token_delta} " <>
        "accuracy_delta=#{Float.round(measurements.accuracy_delta, 4)}"
    )
  end

  def handle_event([:bench_arena, :groundtrace, :emitted], measurements, metadata, _config) do
    Logger.debug(
      "[BenchArena] Groundtrace ##{measurements.record_count} " <>
        "run=#{metadata.run_id} subtask=#{metadata.subtask_id} " <>
        "adapter=#{metadata.adapter}"
    )
  end
end
