defmodule BenchArena.TelemetryTest do
  use ExUnit.Case, async: false

  alias BenchArena.Telemetry

  describe "events/0" do
    test "returns list of event names" do
      events = Telemetry.events()
      assert is_list(events)
      assert length(events) == 2
    end

    test "includes run complete event" do
      events = Telemetry.events()
      assert [:bench_arena, :run, :complete] in events
    end

    test "includes comparison complete event" do
      events = Telemetry.events()
      assert [:bench_arena, :comparison, :complete] in events
    end
  end

  describe "attach/0 and detach/0" do
    test "attach and detach without error" do
      assert :ok = Telemetry.attach()
      assert :ok = Telemetry.detach()
    end

    test "handles double detach gracefully" do
      Telemetry.attach()
      Telemetry.detach()
      # Second detach returns error
      result = Telemetry.detach()
      assert result == {:error, :not_found}
    end
  end
end
