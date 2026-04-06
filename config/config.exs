import Config

config :bench_arena,
  agent_loop_url: System.get_env("AGENT_LOOP_URL") || "http://localhost:4001",
  stack_csc_url: System.get_env("STACK_CSC_URL") || "http://localhost:4003",
  stack_token_gov_url: System.get_env("STACK_TOKEN_GOV_URL") || "http://localhost:4002",
  adapter_timeout_ms: String.to_integer(System.get_env("ADAPTER_TIMEOUT_MS") || "30000"),
  results_dir: System.get_env("BENCH_RESULTS_DIR") || "bench_results",
  perplexity_api_key: System.get_env("PERPLEXITY_API_KEY"),
  anthropic_api_key: System.get_env("ANTHROPIC_API_KEY"),
  openai_api_key: System.get_env("OPENAI_API_KEY"),
  gemini_api_key: System.get_env("GEMINI_API_KEY")

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:run_id, :tier, :adapter]

if config_env() == :test do
  config :bench_arena, adapter_retry: false
end
