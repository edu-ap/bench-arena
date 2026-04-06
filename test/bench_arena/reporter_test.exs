defmodule BenchArena.ReporterTest do
  use ExUnit.Case, async: true

  alias BenchArena.Reporter

  @sample_summary %{
    agent_loop: %{
      count: 10,
      mean_latency_ms: 150.0,
      p50: 140.0,
      p99: 300.0,
      mean_tokens: 250.0,
      mean_accuracy: 0.75,
      pass_rate: 0.8
    },
    stack: %{
      count: 10,
      mean_latency_ms: 450.0,
      p50: 420.0,
      p99: 800.0,
      mean_tokens: 320.0,
      mean_accuracy: 0.9,
      pass_rate: 0.95
    }
  }

  @sample_tradeoff %{
    latency_delta_ms: 300.0,
    token_delta: 70.0,
    accuracy_delta: 0.15,
    pi_score: -0.157
  }

  describe "generate_markdown/3" do
    test "includes run ID" do
      md = Reporter.generate_markdown("run-123", @sample_summary, @sample_tradeoff)
      assert String.contains?(md, "run-123")
    end

    test "includes summary table header" do
      md = Reporter.generate_markdown("run-123", @sample_summary, @sample_tradeoff)
      assert String.contains?(md, "Summary Table")
    end

    test "includes metric rows" do
      md = Reporter.generate_markdown("run-123", @sample_summary, @sample_tradeoff)
      assert String.contains?(md, "Mean Latency")
      assert String.contains?(md, "Mean Tokens")
      assert String.contains?(md, "Pass Rate")
    end

    test "includes tradeoff analysis" do
      md = Reporter.generate_markdown("run-123", @sample_summary, @sample_tradeoff)
      assert String.contains?(md, "Tradeoff Analysis")
      assert String.contains?(md, "300.0")
    end

    test "includes pi-score" do
      md = Reporter.generate_markdown("run-123", @sample_summary, @sample_tradeoff)
      assert String.contains?(md, "π-Score")
    end

    test "includes recommendations section" do
      md = Reporter.generate_markdown("run-123", @sample_summary, @sample_tradeoff)
      assert String.contains?(md, "Recommendations")
    end

    test "includes date" do
      md = Reporter.generate_markdown("run-123", @sample_summary, @sample_tradeoff)
      assert String.contains?(md, Date.utc_today() |> Date.to_iso8601())
    end

    test "handles empty summary" do
      md = Reporter.generate_markdown("run-empty", %{}, %{latency_delta_ms: 0.0, token_delta: 0.0, accuracy_delta: 0.0, pi_score: 0.0})
      assert String.contains?(md, "run-empty")
    end
  end

  describe "generate_html/3" do
    test "includes DOCTYPE declaration" do
      html = Reporter.generate_html("run-123", @sample_summary, @sample_tradeoff)
      assert String.contains?(html, "<!DOCTYPE html>")
    end

    test "includes run ID" do
      html = Reporter.generate_html("run-123", @sample_summary, @sample_tradeoff)
      assert String.contains?(html, "run-123")
    end

    test "includes inline CSS" do
      html = Reporter.generate_html("run-123", @sample_summary, @sample_tradeoff)
      assert String.contains?(html, "<style>")
    end

    test "includes dark/light toggle" do
      html = Reporter.generate_html("run-123", @sample_summary, @sample_tradeoff)
      assert String.contains?(html, "Toggle Theme")
    end

    test "includes summary cards" do
      html = Reporter.generate_html("run-123", @sample_summary, @sample_tradeoff)
      assert String.contains?(html, "card")
      assert String.contains?(html, "Mean Latency")
    end

    test "includes SVG bar chart" do
      html = Reporter.generate_html("run-123", @sample_summary, @sample_tradeoff)
      assert String.contains?(html, "<svg")
      assert String.contains?(html, "<rect")
    end

    test "includes sortable table with JavaScript" do
      html = Reporter.generate_html("run-123", @sample_summary, @sample_tradeoff)
      assert String.contains?(html, "sortTable")
      assert String.contains?(html, "<script>")
    end

    test "includes pi-score display" do
      html = Reporter.generate_html("run-123", @sample_summary, @sample_tradeoff)
      assert String.contains?(html, "pi-score")
    end

    test "uses color classes for tradeoff rows" do
      html = Reporter.generate_html("run-123", @sample_summary, @sample_tradeoff)
      assert String.contains?(html, "win-")
    end

    test "includes adapter color in SVG" do
      html = Reporter.generate_html("run-123", @sample_summary, @sample_tradeoff)
      assert String.contains?(html, "#7dcfff") or String.contains?(html, "#9ece6a")
    end
  end

  describe "generate/4" do
    test "generates markdown by default" do
      {:ok, content} = Reporter.generate("run-123", @sample_summary, @sample_tradeoff)
      assert String.contains?(content, "# BenchArena Run Report")
    end

    test "generates html when specified" do
      {:ok, content} = Reporter.generate("run-123", @sample_summary, @sample_tradeoff, format: :html)
      assert String.contains?(content, "<!DOCTYPE html>")
    end

    test "writes to file when output specified" do
      path = Path.join(System.tmp_dir!(), "test_report_#{System.unique_integer([:positive])}.md")

      {:ok, content} = Reporter.generate("run-123", @sample_summary, @sample_tradeoff, output: path)
      assert File.exists?(path)
      assert File.read!(path) == content

      File.rm!(path)
    end
  end
end
