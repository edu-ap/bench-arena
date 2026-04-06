Application.ensure_all_started(:bench_arena)

alias BenchArena.{Runner, Corpus, MetricCollector, Scorer}

MetricCollector.reset()

questions = Corpus.all()
IO.puts("Loaded #{length(questions)} questions across #{questions |> Enum.map(& &1.tier) |> Enum.uniq() |> length()} tiers")

# Adapters to run
adapters = [:baseline, :agent_loop, :stack, :perplexity_standard, :perplexity_deep_research,
            :perplexity_model_council, :claude_code, :codex, :gemini_cli]

all_results = []

results_by_adapter = Enum.reduce(adapters, %{}, fn adapter, acc ->
  IO.puts("\n=== Running adapter: #{adapter} ===")
  adapter_results = Enum.map(questions, fn q ->
    result = Runner.run_question(q, adapter)
    answer = case result.answer do
      nil -> ""
      a -> a
    end
    score = Scorer.score(answer, q)

    status = if result.error, do: "ERR:#{inspect(result.error)}", else: "OK"
    IO.puts("[#{adapter}/tier#{q.tier}/#{q.id}] #{Float.round(result.latency_ms, 1)}ms #{result.total_tokens}tok score=#{Float.round(score, 2)} #{status}")

    {result, score}
  end)

  # Record all results
  Enum.each(adapter_results, fn {r, score} ->
    MetricCollector.record(Map.from_struct(r) |> Map.put(:accuracy, score))
  end)

  Map.put(acc, adapter, adapter_results)
end)

# Summary
IO.puts("\n\n=== SUMMARY ===")

summary_data = Enum.map(adapters, fn adapter ->
  adapter_results = Map.get(results_by_adapter, adapter, [])
  scores = Enum.map(adapter_results, fn {_r, score} -> score end)
  errors = Enum.count(adapter_results, fn {r, _score} -> r.error != nil end)
  successes = length(adapter_results) - errors
  mean_score = if length(scores) > 0, do: Enum.sum(scores) / length(scores), else: 0.0
  latencies = adapter_results
    |> Enum.filter(fn {r, _} -> r.error == nil end)
    |> Enum.map(fn {r, _} -> r.latency_ms end)
  mean_latency = if length(latencies) > 0, do: Enum.sum(latencies) / length(latencies), else: 0.0
  tokens = adapter_results
    |> Enum.filter(fn {r, _} -> r.error == nil end)
    |> Enum.map(fn {r, _} -> r.total_tokens end)
  mean_tokens = if length(tokens) > 0, do: Enum.sum(tokens) / length(tokens), else: 0.0

  # Per-tier scores
  tier_scores = for tier <- 1..5 do
    tier_results = adapter_results |> Enum.filter(fn {r, _} -> r.tier == tier end)
    tier_scores_list = Enum.map(tier_results, fn {_, s} -> s end)
    tier_mean = if length(tier_scores_list) > 0, do: Enum.sum(tier_scores_list) / length(tier_scores_list), else: 0.0
    {tier, Float.round(tier_mean, 4)}
  end |> Map.new()

  status = cond do
    successes > 0 -> "live"
    errors > 0 -> "error"
    true -> "not_run"
  end

  IO.puts("  #{adapter}: mean_acc=#{Float.round(mean_score, 4)} mean_lat=#{Float.round(mean_latency, 1)}ms mean_tok=#{Float.round(mean_tokens, 0)} success=#{successes}/#{length(adapter_results)} status=#{status}")

  %{
    adapter: Atom.to_string(adapter),
    status: status,
    mean_accuracy: Float.round(mean_score, 4),
    mean_latency_ms: Float.round(mean_latency, 1),
    mean_tokens: Float.round(mean_tokens, 0),
    successes: successes,
    errors: errors,
    total_questions: length(adapter_results),
    tier_scores: tier_scores
  }
end)

# Write all detailed results
File.mkdir_p!("bench_results")
all_detail = Enum.flat_map(adapters, fn adapter ->
  adapter_results = Map.get(results_by_adapter, adapter, [])
  Enum.map(adapter_results, fn {r, score} ->
    %{
      question_id: r.question_id,
      tier: r.tier,
      adapter: Atom.to_string(r.adapter),
      latency_ms: r.latency_ms,
      tokens_in: r.tokens_in,
      tokens_out: r.tokens_out,
      total_tokens: r.total_tokens,
      answer: r.answer,
      accuracy: score,
      error: if(r.error, do: inspect(r.error)),
      timestamp: r.timestamp
    }
  end)
end)

run_id = "real_run_#{Date.utc_today() |> Date.to_iso8601()}"
json_path = "bench_results/#{run_id}.json"
File.write!(json_path, Jason.encode!(%{
  run_id: run_id,
  timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
  summary: summary_data,
  results: all_detail
}, pretty: true))
IO.puts("\nDetailed results written to #{json_path}")

# Write summary JSON
summary_json = Jason.encode!(%{
  run_id: run_id,
  timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
  adapters: summary_data
}, pretty: true)

IO.puts("\n=== JSON SUMMARY ===")
IO.puts(summary_json)
