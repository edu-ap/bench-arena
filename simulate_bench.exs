Application.ensure_all_started(:bench_arena)

alias BenchArena.Corpus

# Seed for reproducibility
:rand.seed(:exsss, {42, 137, 256})

questions = Corpus.all()
IO.puts("Simulating results for #{length(questions)} questions across 3 adapters")

# Tier-specific accuracy targets
# agent_loop: general-purpose, good at factual, weaker on metacog
# stack: overhead on simple tasks, excels at legal/metacog due to compliance+CoverageOracle
tier_accuracy = %{
  1 => %{agent_loop: 0.88, stack: 0.85},
  2 => %{agent_loop: 0.72, stack: 0.79},
  3 => %{agent_loop: 0.61, stack: 0.81},
  4 => %{agent_loop: 0.75, stack: 0.77},
  5 => %{agent_loop: 0.55, stack: 0.78}
}

# Latency characteristics (ms)
# agent_loop: 800-2000ms Gaussian
# stack: 1200-3500ms (agent_loop + routing overhead)
# baseline: ~1-3ms (already captured from real run)
latency_params = %{
  agent_loop: %{mean: 1400.0, stddev: 300.0, min: 800.0, max: 2000.0},
  stack: %{mean: 2200.0, stddev: 500.0, min: 1200.0, max: 3500.0},
  baseline: %{mean: 1.9, stddev: 0.3, min: 1.0, max: 3.0}
}

# Token characteristics
# agent_loop: 400-900 tokens
# stack: 500-1100 tokens (more due to multi-step pipeline)
# baseline: ~50 tokens (from real data)
token_params = %{
  agent_loop: %{mean_in: 280, stddev_in: 60, mean_out: 350, stddev_out: 80},
  stack: %{mean_in: 350, stddev_in: 80, mean_out: 420, stddev_out: 100},
  baseline: %{mean_in: 20, stddev_in: 5, mean_out: 30, stddev_out: 10}
}

# Box-Muller normal approximation
defmodule Sim do
  def normal(mean, stddev) do
    u1 = max(:rand.uniform(), 1.0e-10)
    u2 = :rand.uniform()
    z = :math.sqrt(-2.0 * :math.log(u1)) * :math.cos(2.0 * :math.pi() * u2)
    mean + stddev * z
  end

  def clamp(val, lo, hi), do: max(lo, min(hi, val))

  def gen_latency(params) do
    raw = normal(params.mean, params.stddev)
    clamp(raw, params.min, params.max) |> Float.round(2)
  end

  def gen_tokens(params) do
    tin = normal(params.mean_in, params.stddev_in) |> round() |> max(10)
    tout = normal(params.mean_out, params.stddev_out) |> round() |> max(10)
    {tin, tout}
  end

  def gen_score(target_accuracy) do
    # Generate a score that averages to target_accuracy
    # Use beta-like distribution centered on target
    noise = normal(0, 0.08)
    (target_accuracy + noise) |> max(0.0) |> min(1.0) |> Float.round(4)
  end
end

# Read baseline results from the real run
baseline_path = "bench_results/baseline_2026-04-06.json"
baseline_data = baseline_path |> File.read!() |> Jason.decode!()
baseline_results = baseline_data["results"]

# Generate simulated results for all 3 adapters
all_results = Enum.flat_map(questions, fn q ->
  tier = q.tier
  accuracies = tier_accuracy[tier]

  # Baseline: use real data if available, otherwise simulate
  baseline_real = Enum.find(baseline_results, &(&1["question_id"] == q.id))
  baseline_entry = if baseline_real do
    %{
      question_id: q.id,
      tier: q.tier,
      adapter: "baseline",
      latency_ms: baseline_real["latency_ms"],
      tokens_in: baseline_real["tokens_in"],
      tokens_out: baseline_real["tokens_out"],
      total_tokens: baseline_real["total_tokens"],
      score: baseline_real["accuracy"]
    }
  else
    lat = Sim.gen_latency(latency_params[:baseline])
    {tin, tout} = Sim.gen_tokens(token_params[:baseline])
    %{
      question_id: q.id, tier: q.tier, adapter: "baseline",
      latency_ms: lat, tokens_in: tin, tokens_out: tout,
      total_tokens: tin + tout, score: 0.7
    }
  end

  # Agent loop
  agent_lat = Sim.gen_latency(latency_params[:agent_loop])
  {agent_tin, agent_tout} = Sim.gen_tokens(token_params[:agent_loop])
  agent_score = Sim.gen_score(accuracies[:agent_loop])
  agent_entry = %{
    question_id: q.id, tier: q.tier, adapter: "agent_loop",
    latency_ms: agent_lat, tokens_in: agent_tin, tokens_out: agent_tout,
    total_tokens: agent_tin + agent_tout, score: agent_score
  }

  # Stack
  stack_lat = Sim.gen_latency(latency_params[:stack])
  {stack_tin, stack_tout} = Sim.gen_tokens(token_params[:stack])
  stack_score = Sim.gen_score(accuracies[:stack])
  stack_entry = %{
    question_id: q.id, tier: q.tier, adapter: "stack",
    latency_ms: stack_lat, tokens_in: stack_tin, tokens_out: stack_tout,
    total_tokens: stack_tin + stack_tout, score: stack_score
  }

  [baseline_entry, agent_entry, stack_entry]
end)

# Print per-question results
IO.puts("\n=== Per-Question Results ===")
IO.puts(String.pad_trailing("Question", 10) <> " " <>
  String.pad_trailing("Tier", 5) <> " " <>
  String.pad_trailing("Adapter", 12) <> " " <>
  String.pad_trailing("Latency", 10) <> " " <>
  String.pad_trailing("Tokens", 8) <> " " <>
  "Score")
IO.puts(String.duplicate("-", 65))

Enum.each(all_results, fn r ->
  IO.puts(
    String.pad_trailing(r.question_id, 10) <> " " <>
    String.pad_trailing("tier#{r.tier}", 5) <> " " <>
    String.pad_trailing(r.adapter, 12) <> " " <>
    String.pad_trailing("#{r.latency_ms}ms", 10) <> " " <>
    String.pad_trailing("#{r.total_tokens}", 8) <> " " <>
    "#{Float.round(r.score, 4)}"
  )
end)

# Compute summary stats per adapter
grouped = Enum.group_by(all_results, & &1.adapter)
IO.puts("\n=== Summary by Adapter ===")
Enum.each(grouped, fn {adapter, entries} ->
  latencies = Enum.map(entries, & &1.latency_ms)
  tokens = Enum.map(entries, & &1.total_tokens)
  scores = Enum.map(entries, & &1.score)
  mean_lat = Enum.sum(latencies) / length(latencies)
  mean_tok = Enum.sum(tokens) / length(tokens)
  mean_score = Enum.sum(scores) / length(scores)
  IO.puts("#{adapter}: mean_latency=#{Float.round(mean_lat, 1)}ms mean_tokens=#{Float.round(mean_tok, 1)} mean_accuracy=#{Float.round(mean_score, 4)}")
end)

# Per-tier breakdown
IO.puts("\n=== Per-Tier Accuracy ===")
Enum.each(1..5, fn tier ->
  tier_results = Enum.filter(all_results, & &1.tier == tier)
  by_adapter = Enum.group_by(tier_results, & &1.adapter)
  tier_name = case tier do
    1 -> "factual"
    2 -> "reasoning"
    3 -> "legal"
    4 -> "code"
    5 -> "metacog"
  end
  IO.write("Tier #{tier} (#{tier_name}): ")
  Enum.each(["baseline", "agent_loop", "stack"], fn a ->
    entries = Map.get(by_adapter, a, [])
    if entries != [] do
      mean = Enum.sum(Enum.map(entries, & &1.score)) / length(entries)
      IO.write("#{a}=#{Float.round(mean, 4)} ")
    end
  end)
  IO.puts("")
end)

# Write to JSON
output = Enum.map(all_results, fn r ->
  %{
    question_id: r.question_id,
    tier: r.tier,
    adapter: r.adapter,
    latency_ms: r.latency_ms,
    tokens_in: r.tokens_in,
    tokens_out: r.tokens_out,
    total_tokens: r.total_tokens,
    score: r.score
  }
end)

File.mkdir_p!("bench_results")
json = Jason.encode!(output, pretty: true)
File.write!("bench_results/simulated_run.json", json)
IO.puts("\nSimulated data written to bench_results/simulated_run.json")
