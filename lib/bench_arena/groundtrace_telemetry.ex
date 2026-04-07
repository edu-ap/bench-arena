defmodule BenchArena.GroundtraceTelemetry do
  @moduledoc """
  Groundtrace telemetry — builds tamper-evident GroundtraceRecords for
  each adapter step in a BenchArena run.

  Maintains a process-local `run_id` and `prev_record_hash` state via
  an Agent process. After each question run, `emit/3` builds a
  GroundtraceRecord and appends it to the AuditStore file at
  `bench_results/audit_store_<run_id>.jsonl`.

  ## Usage

      {:ok, _pid} = BenchArena.GroundtraceTelemetry.start_link(run_id: "run-001")
      BenchArena.GroundtraceTelemetry.emit(question_id, result, metadata)
      BenchArena.GroundtraceTelemetry.stop()

  ## AuditStore

  The AuditStore is a JSON-Lines file where each line is a complete
  GroundtraceRecord. The hash chain links records sequentially,
  making any tampering detectable. Gracefully no-ops if the store
  path is not writable.
  """

  use Agent
  require Logger

  @results_dir "bench_results"

  @doc """
  Start the groundtrace telemetry agent with a run_id.
  """
  @spec start_link(keyword()) :: Agent.on_start()
  def start_link(opts \\ []) do
    run_id = Keyword.get(opts, :run_id, generate_run_id())
    store_path = audit_store_path(run_id)
    ensure_results_dir()

    Agent.start_link(
      fn ->
        %{
          run_id: run_id,
          prev_record_hash: "",
          store_path: store_path,
          record_count: 0
        }
      end,
      name: __MODULE__
    )
  end

  @doc """
  Emit a GroundtraceRecord after a question run.

  Called after each adapter step with the subtask_id (question.id),
  result map, and metadata. Builds a record, appends to the AuditStore,
  and updates the hash chain state.

  Gracefully no-ops if the telemetry agent is not running or the
  AuditStore path is not writable.
  """
  @spec emit(String.t(), map(), map()) :: :ok | {:error, term()}
  def emit(subtask_id, result, metadata) do
    if agent_alive?() do
      do_emit(subtask_id, result, metadata)
    else
      :ok
    end
  rescue
    _ -> :ok
  end

  @doc """
  Stop the groundtrace telemetry agent.
  """
  @spec stop() :: :ok
  def stop do
    if agent_alive?() do
      Agent.stop(__MODULE__)
    end

    :ok
  end

  @doc """
  Get the current state (run_id, record_count, store_path).
  """
  @spec state() :: map() | nil
  def state do
    if agent_alive?() do
      Agent.get(__MODULE__, & &1)
    end
  end

  # ── Private ──────────────────────────────────────────────────────────────

  defp do_emit(subtask_id, result, metadata) do
    state = Agent.get(__MODULE__, & &1)

    fields = %{
      run_id: state.run_id,
      subtask_id: subtask_id,
      adapter: Map.get(result, :adapter, :unknown),
      model_id: Map.get(metadata, :model_id, ""),
      model_temperature: Map.get(metadata, :model_temperature, 0.0),
      prompt_hash: compute_prompt_hash(metadata),
      retrieved_sources: Map.get(metadata, :retrieved_sources, []),
      raw_response_hash: compute_response_hash(result),
      tokens_in: Map.get(result, :tokens_in, 0),
      tokens_out: Map.get(result, :tokens_out, 0),
      latency_ms: round_latency(Map.get(result, :latency_ms, 0)),
      confabulum_verdict: Map.get(result, :confabulum_verdict, %{status: :pass}),
      confidence_score: Map.get(result, :confidence_score, 0.0),
      certainty_vocab: Map.get(result, :certainty_vocab, :uncertain),
      score: Map.get(result, :score, 0.0)
    }

    {:ok, record} = build_record(fields, state.prev_record_hash)

    case append_record(record, state.store_path) do
      :ok ->
        Agent.update(__MODULE__, fn s ->
          %{s | prev_record_hash: record.record_hash, record_count: s.record_count + 1}
        end)

        :telemetry.execute(
          [:bench_arena, :groundtrace, :emitted],
          %{record_count: state.record_count + 1},
          %{run_id: state.run_id, subtask_id: subtask_id, adapter: fields.adapter}
        )

        :ok

      {:error, reason} ->
        Logger.warning(
          "[GroundtraceTelemetry] Failed to append record: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  defp build_record(fields, prev_hash) do
    record_id = generate_uuid()
    timestamp = DateTime.utc_now()

    record = %{
      record_id: record_id,
      run_id: fields.run_id,
      subtask_id: fields.subtask_id,
      adapter: to_string(fields.adapter),
      model_id: fields.model_id,
      model_temperature: fields.model_temperature,
      prompt_hash: fields.prompt_hash,
      retrieved_sources: fields.retrieved_sources,
      raw_response_hash: fields.raw_response_hash,
      tokens_in: fields.tokens_in,
      tokens_out: fields.tokens_out,
      latency_ms: fields.latency_ms,
      confabulum_verdict: fields.confabulum_verdict,
      confidence_score: fields.confidence_score,
      certainty_vocab: to_string(fields.certainty_vocab),
      score: fields.score,
      timestamp_utc: DateTime.to_iso8601(timestamp),
      prev_record_hash: prev_hash
    }

    content = hash_content(record)
    record_hash = sha256(content)

    {:ok, Map.put(record, :record_hash, record_hash)}
  end

  defp append_record(record, store_path) do
    json_line = Jason.encode!(record)

    case File.open(store_path, [:append, :utf8]) do
      {:ok, file} ->
        IO.write(file, json_line <> "\n")
        File.close(file)
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    _ -> {:error, :write_failed}
  end

  defp hash_content(record) do
    [
      record.record_id,
      record.run_id,
      record.subtask_id,
      record.adapter,
      record.model_id,
      to_string(record.model_temperature),
      record.prompt_hash,
      Jason.encode!(record.retrieved_sources),
      record.raw_response_hash,
      to_string(record.tokens_in),
      to_string(record.tokens_out),
      to_string(record.latency_ms),
      Jason.encode!(record.confabulum_verdict),
      to_string(record.confidence_score),
      record.certainty_vocab,
      to_string(record.score),
      record.timestamp_utc,
      record.prev_record_hash
    ]
    |> Enum.join("|")
  end

  defp sha256(content) do
    :crypto.hash(:sha256, content)
    |> Base.encode16(case: :lower)
  end

  defp compute_prompt_hash(metadata) do
    question = Map.get(metadata, :question, %{})

    content =
      case question do
        %{question: q} -> q
        %{text: t} -> t
        _ -> inspect(question)
      end

    sha256(content)
  end

  defp compute_response_hash(result) do
    answer = Map.get(result, :answer, "") || ""
    sha256(answer)
  end

  defp round_latency(latency) when is_float(latency), do: round(latency)
  defp round_latency(latency) when is_integer(latency), do: latency
  defp round_latency(_), do: 0

  defp audit_store_path(run_id) do
    Path.join(@results_dir, "audit_store_#{run_id}.jsonl")
  end

  defp ensure_results_dir do
    File.mkdir_p(@results_dir)
  end

  defp agent_alive? do
    case Process.whereis(__MODULE__) do
      nil -> false
      pid -> Process.alive?(pid)
    end
  end

  defp generate_run_id do
    "run-#{System.system_time(:millisecond)}-#{:rand.uniform(9999)}"
  end

  defp generate_uuid do
    <<a::48, _::4, b::12, _::2, c::62>> = :crypto.strong_rand_bytes(16)

    <<a::48, 4::4, b::12, 2::2, c::62>>
    |> Base.encode16(case: :lower)
    |> String.replace(
      ~r/^(.{8})(.{4})(.{4})(.{4})(.{12})$/,
      "\\1-\\2-\\3-\\4-\\5"
    )
  end
end
