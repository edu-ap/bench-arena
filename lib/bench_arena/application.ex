defmodule BenchArena.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      BenchArena.MetricCollector
    ]

    opts = [strategy: :one_for_one, name: BenchArena.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
