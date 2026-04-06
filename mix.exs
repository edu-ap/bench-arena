defmodule BenchArena.MixProject do
  use Mix.Project

  def project do
    [
      app: :bench_arena,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      aliases: aliases(),
      name: "BenchArena",
      source_url: "https://github.com/edu-ap/bench-arena",
      docs: [main: "readme", extras: ["README.md"]]
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {BenchArena.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:benchee, "~> 1.3"},
      {:jason, "~> 1.4"},
      {:req, "~> 0.5"},
      {:telemetry, "~> 1.2"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:mox, "~> 1.1", only: :test},
      {:elan, path: "../elan-build", optional: true},
      {:csc, path: "../composable-skill-compiler/elixir/csc", optional: true},
      {:token_gov, path: "../tokengov/elixir/token_gov", optional: true}
    ]
  end

  defp aliases do
    []
  end
end
