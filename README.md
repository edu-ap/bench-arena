# BenchArena

Elixir benchmarking harness that measures **agent loop vs stack** performance across three dimensions: **latency** (wall clock + CPU), **token usage**, and **accuracy**. This is a dogfooding tool — the stack evaluates itself.

## Architecture

```
┌─────────────────────────────────────────────────┐
│                  BenchArena                       │
│                                                   │
│  ┌──────────┐  ┌──────────┐  ┌──────────────┐  │
│  │  Corpus   │  │  Runner   │  │ MetricCollect│  │
│  │ (JSON Q's)│─>│ (execute) │─>│ (ETS store)  │  │
│  └──────────┘  └────┬─────┘  └──────┬───────┘  │
│                     │               │            │
│         ┌───────────┼───────┐       │            │
│         ▼           ▼       ▼       ▼            │
│  ┌──────────┐ ┌─────────┐ ┌────┐ ┌──────────┐  │
│  │AgentLoop │ │  Stack   │ │Base│ │Comparator│  │
│  │ Adapter  │ │ Adapter  │ │line│ │          │  │
│  └────┬─────┘ └────┬────┘ └────┘ └────┬─────┘  │
│       │            │                    │        │
│       ▼            ▼                    ▼        │
│  ┌─────────┐ ┌──────────┐       ┌──────────┐   │
│  │Elan HTTP│ │CSC+TokenGov       │ Reporter  │   │
│  │  :4001  │ │ :4003/:4002│      │ (MD/HTML) │   │
│  └─────────┘ └──────────┘       └──────────┘   │
│                                                   │
│  ┌──────────┐  ┌──────────┐  ┌──────────────┐  │
│  │  Scorer   │  │Telemetry │  │  Mix Tasks   │  │
│  │(3 methods)│  │(:telemetry│  │(run/compare/ │  │
│  └──────────┘  │ events)  │  │  report)     │  │
│                └──────────┘  └──────────────┘  │
└─────────────────────────────────────────────────┘
```

## Quick Start

```bash
mix deps.get
mix compile

# Run tier 1 with 5 questions using baseline adapter
mix bench_arena.run --tier 1 --n 5 --adapter baseline

# Run all tiers, all adapters
mix bench_arena.run

# Compare results
mix bench_arena.compare --run-id <run_id>

# Generate report
mix bench_arena.report --run-id <run_id> --format html --output report.html
```

## Metrics

### Latency Delta
`latency_delta_ms = stack_latency - agent_loop_latency`
- **Positive** = stack is slower
- **Negative** = stack is faster

### Token Delta
`token_delta = stack_tokens - agent_loop_tokens`
- **Positive** = stack uses more tokens
- **Negative** = stack uses fewer tokens

### Accuracy Delta
`accuracy_delta = stack_accuracy - agent_loop_accuracy`
- **Positive** = stack is more accurate
- **Negative** = stack is less accurate

### π-Score (Tradeoff Score)
```
π = accuracy_delta - 0.001 × latency_delta - 0.0001 × token_delta
```

The π-score weighs accuracy gains against latency and token costs:
- **π > 0**: Stack's accuracy gain outweighs its cost overhead
- **π < 0**: Agent loop is the better value proposition
- **π ≈ 0**: No clear winner — tradeoffs are balanced

## Adapters

### Agent Loop Adapter
- Calls Elan HTTP API at `localhost:4001`
- `GET /health` for availability check
- `POST /run_skill` with `skill_id: "agent_loop"`
- Timeout: 30s (configurable via `ADAPTER_TIMEOUT_MS`)

### Stack Adapter
- Routes through CSC compile (`localhost:4003/compile`)
- Routes through TokenGov policy (`localhost:4002/governance/proposals`)
- Full mediated execution pipeline

### Baseline Adapter
- No stack, no loop — returns stub answer
- Used as a floor comparison
- Always succeeds, ~1ms latency

## Question Tiers

| Tier | Name | Count | Tests |
|------|------|-------|-------|
| 1 | Factual | 10 | Short-answer domain knowledge (entropy, UCB1, IRAP, etc.) |
| 2 | Reasoning | 8 | Multi-step inference chains (laxity probes, sorry_depth, etc.) |
| 3 | Legal | 6 | Legal AI compliance (IRAP ISM, EU AI Act, GDPR, CCPA) |
| 4 | Code | 6 | Code generation/review (Elixir, Lean 4, cryptography) |
| 5 | Metacognitive | 5 | Self-assessment (sorry_depth SLO, DriftSensor, π-score) |

**Total: 35 questions**

## Scoring Methods

1. **Exact Match** — Normalized string comparison → 0.0 or 1.0
2. **Semantic** — Jaccard similarity on lowercased word sets → 0.0–1.0
3. **Rubric** — Keyword presence against criteria list → 0.0–1.0

## Report Formats

### Markdown
- Summary table with all metrics per adapter
- Tradeoff analysis with deltas and interpretations
- π-score with recommendation
- Per-tier breakdown

### HTML
- Standalone with inline CSS (dark/light theme toggle)
- Summary cards for each adapter
- SVG bar chart comparing latency
- Sortable results table
- Color-coded tradeoff rows (green=stack wins, amber=tie, blue=agent wins)

## Configuration

Environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `AGENT_LOOP_URL` | `http://localhost:4001` | Elan agent loop endpoint |
| `STACK_CSC_URL` | `http://localhost:4003` | CSC compile endpoint |
| `STACK_TOKEN_GOV_URL` | `http://localhost:4002` | TokenGov endpoint |
| `ADAPTER_TIMEOUT_MS` | `30000` | Adapter request timeout |
| `BENCH_RESULTS_DIR` | `bench_results` | Output directory for results JSON |

## Expected Tradeoff Profile

Based on initial hypothesis:

| Dimension | Agent Loop | Stack | Delta |
|-----------|-----------|-------|-------|
| Latency | Fast (50-200ms) | Slower (+200-800ms) | Stack adds 200-800ms |
| Tokens | Lean (100-300) | Heavier (+10-30%) | Stack uses 10-30% more |
| Accuracy (Factual) | Good (0.7-0.8) | Similar (0.7-0.85) | Marginal stack gain |
| Accuracy (Reasoning) | Fair (0.5-0.7) | Better (0.65-0.85) | Stack gains 15-25% |
| Accuracy (Legal) | Variable (0.4-0.7) | Better (0.6-0.85) | Stack gains 15-25% |

**Hypothesis**: Stack adds meaningful accuracy on reasoning and legal tiers that justifies the latency/token overhead for compliance-sensitive workloads.

## Testing

```bash
mix test                          # Run all tests
mix test test/bench_arena/scorer_test.exs  # Run specific test file
```

## Development

```bash
mix compile                        # Compile
mix run bench/arena_bench.exs      # Run Benchee benchmarks
```
