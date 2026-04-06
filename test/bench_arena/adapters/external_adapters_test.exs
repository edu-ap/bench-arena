defmodule BenchArena.Adapters.ExternalAdaptersTest do
  use ExUnit.Case, async: true

  import BenchArena.TestHelpers

  @adapters [
    {BenchArena.Adapters.PerplexityStandardAdapter, :perplexity_standard,
     :perplexity_api_key},
    {BenchArena.Adapters.PerplexityDeepResearchAdapter, :perplexity_deep_research,
     :perplexity_api_key},
    {BenchArena.Adapters.PerplexityModelCouncilAdapter, :perplexity_model_council,
     :perplexity_api_key},
    {BenchArena.Adapters.ClaudeCodeAdapter, :claude_code, :anthropic_api_key},
    {BenchArena.Adapters.CodexAdapter, :codex, :openai_api_key},
    {BenchArena.Adapters.GeminiCliAdapter, :gemini_cli, :gemini_api_key}
  ]

  for {mod, name, config_key} <- @adapters do
    mod_str = inspect(mod)
    name_str = Atom.to_string(name)

    test "#{mod_str} returns {:error, :credentials_not_configured} when API key is not set" do
      config_key = unquote(config_key)
      mod = unquote(mod)

      original = Application.get_env(:bench_arena, config_key)
      Application.put_env(:bench_arena, config_key, nil)

      env_var = config_key |> Atom.to_string() |> String.upcase()
      original_env = System.get_env(env_var)
      System.delete_env(env_var)

      try do
        question = sample_question()
        assert {:error, :credentials_not_configured} = mod.execute(question)
      after
        if original do
          Application.put_env(:bench_arena, config_key, original)
        end

        if original_env do
          System.put_env(env_var, original_env)
        end
      end
    end

    test "#{mod_str} implements BenchArena.Adapter behaviour (exports execute/1)" do
      Code.ensure_loaded!(unquote(mod))
      assert function_exported?(unquote(mod), :execute, 1)
    end

    test "#{mod_str} is registered as :#{name_str} in runner adapter map" do
      adapter_modules = %{
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

      assert Map.get(adapter_modules, unquote(name)) == unquote(mod)
    end
  end

  describe "MetricCollector.adapter_groups/0" do
    test "returns correct adapter groupings" do
      groups = BenchArena.MetricCollector.adapter_groups()

      assert groups.stack_internal == [:baseline, :agent_loop, :stack]

      assert groups.perplexity == [
               :perplexity_standard,
               :perplexity_deep_research,
               :perplexity_model_council
             ]

      assert groups.external_ai == [:claude_code, :codex, :gemini_cli]
    end

    test "all adapters in groups cover all 9 adapters" do
      groups = BenchArena.MetricCollector.adapter_groups()
      all_atoms = Enum.flat_map(Map.values(groups), & &1)
      assert length(all_atoms) == 9
    end
  end
end
