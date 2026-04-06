defmodule BenchArena.Reporter do
  @moduledoc """
  Generates Markdown and HTML reports from benchmark results.
  """

  @doc """
  Generate a report in the specified format.

  Options:
    - `:format` - :markdown or :html (default: :markdown)
    - `:output` - file path to write to (optional)
  """
  @spec generate(String.t(), map(), map(), keyword()) :: {:ok, String.t()}
  def generate(run_id, summary, tradeoff, opts \\ []) do
    format = Keyword.get(opts, :format, :markdown)
    output = Keyword.get(opts, :output)

    content =
      case format do
        :markdown -> generate_markdown(run_id, summary, tradeoff)
        :html -> generate_html(run_id, summary, tradeoff)
      end

    if output do
      File.write!(output, content)
    end

    {:ok, content}
  end

  @doc """
  Generate a Markdown report.
  """
  @spec generate_markdown(String.t(), map(), map()) :: String.t()
  def generate_markdown(run_id, summary, tradeoff) do
    date = Date.utc_today() |> Date.to_iso8601()
    total_questions = summary |> Map.values() |> Enum.map(& &1[:count]) |> Enum.filter(&(&1)) |> Enum.sum()
    total_questions = div(max(total_questions, 0), max(map_size(summary), 1))

    """
    # BenchArena Run Report
    Run ID: #{run_id}
    Questions: #{total_questions} | Date: #{date}

    ## Summary Table
    | Metric | #{summary_header(summary)} |
    |--------|#{summary_separator(summary)}|
    #{summary_rows(summary)}

    ## Tradeoff Analysis
    | Dimension | Delta | Interpretation |
    |-----------|-------|----------------|
    | Latency | #{format_delta(tradeoff[:latency_delta_ms] || tradeoff.latency_delta_ms)}ms | #{latency_interpretation(tradeoff)} |
    | Tokens | #{format_delta(tradeoff[:token_delta] || tradeoff.token_delta)} | #{token_interpretation(tradeoff)} |
    | Accuracy | #{format_delta(tradeoff[:accuracy_delta] || tradeoff.accuracy_delta)} | #{accuracy_interpretation(tradeoff)} |

    ## π-Score
    **#{format_delta(tradeoff[:pi_score] || tradeoff.pi_score)}**

    Formula: `accuracy_delta - 0.001 * latency_delta - 0.0001 * token_delta`

    #{pi_recommendation(tradeoff)}

    ## Recommendations
    #{generate_recommendations(summary, tradeoff)}
    """
  end

  @doc """
  Generate an HTML report with inline CSS and SVG charts.
  """
  @spec generate_html(String.t(), map(), map()) :: String.t()
  def generate_html(run_id, summary, tradeoff) do
    date = Date.utc_today() |> Date.to_iso8601()

    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>BenchArena Report — #{run_id}</title>
    <style>
    :root { --bg: #1a1b26; --fg: #c0caf5; --card: #24283b; --accent: #7aa2f7; --green: #9ece6a; --amber: #e0af68; --blue: #7dcfff; }
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', monospace; background: var(--bg); color: var(--fg); margin: 0; padding: 20px; }
    body.light { --bg: #fff; --fg: #333; --card: #f5f5f5; --accent: #2563eb; --green: #16a34a; --amber: #d97706; --blue: #0891b2; }
    .toggle { position: fixed; top: 10px; right: 10px; background: var(--card); border: 1px solid var(--fg); color: var(--fg); padding: 8px 16px; cursor: pointer; border-radius: 4px; }
    .container { max-width: 1200px; margin: 0 auto; }
    h1 { color: var(--accent); }
    .cards { display: grid; grid-template-columns: repeat(auto-fit, minmax(250px, 1fr)); gap: 16px; margin: 20px 0; }
    .card { background: var(--card); padding: 20px; border-radius: 8px; }
    .card h3 { margin: 0 0 10px 0; color: var(--accent); }
    .card .value { font-size: 2em; font-weight: bold; }
    .card .label { opacity: 0.7; font-size: 0.9em; }
    table { width: 100%; border-collapse: collapse; margin: 20px 0; }
    th, td { padding: 10px 14px; text-align: left; border-bottom: 1px solid rgba(255,255,255,0.1); }
    th { background: var(--card); }
    .win-stack { background: rgba(158, 206, 106, 0.15); }
    .win-agent { background: rgba(125, 207, 255, 0.15); }
    .win-tie { background: rgba(224, 175, 104, 0.15); }
    svg { width: 100%; max-width: 800px; }
    .pi-score { font-size: 3em; font-weight: bold; text-align: center; margin: 20px 0; color: var(--accent); }
    </style>
    </head>
    <body>
    <button class="toggle" onclick="document.body.classList.toggle('light')">Toggle Theme</button>
    <div class="container">
    <h1>BenchArena Run Report</h1>
    <p>Run ID: <code>#{run_id}</code> | Date: #{date}</p>

    <div class="cards">
    #{summary_cards(summary)}
    </div>

    <h2>Tradeoff Analysis</h2>
    <table>
    <thead><tr><th>Dimension</th><th>Delta</th><th>Winner</th></tr></thead>
    <tbody>
    #{tradeoff_rows_html(tradeoff)}
    </tbody>
    </table>

    <h2>π-Score</h2>
    <div class="pi-score">#{format_delta(tradeoff[:pi_score] || tradeoff.pi_score)}</div>
    <p style="text-align:center"><code>accuracy_delta - 0.001 × latency_delta - 0.0001 × token_delta</code></p>

    <h2>Latency Comparison</h2>
    #{latency_svg_chart(summary)}

    <h2>Detailed Results</h2>
    <table id="results">
    <thead><tr><th onclick="sortTable(0)">Adapter</th><th onclick="sortTable(1)">Mean Latency</th><th onclick="sortTable(2)">Mean Tokens</th><th onclick="sortTable(3)">Mean Accuracy</th><th onclick="sortTable(4)">Pass Rate</th></tr></thead>
    <tbody>
    #{detail_rows_html(summary)}
    </tbody>
    </table>
    </div>

    <script>
    function sortTable(n) {
      var table = document.getElementById("results");
      var rows = Array.from(table.tBodies[0].rows);
      var asc = table.dataset.sortDir !== "asc";
      rows.sort(function(a, b) {
        var va = a.cells[n].textContent, vb = b.cells[n].textContent;
        var na = parseFloat(va), nb = parseFloat(vb);
        if (!isNaN(na) && !isNaN(nb)) return asc ? na - nb : nb - na;
        return asc ? va.localeCompare(vb) : vb.localeCompare(va);
      });
      rows.forEach(function(r) { table.tBodies[0].appendChild(r); });
      table.dataset.sortDir = asc ? "asc" : "desc";
    }
    </script>
    </body>
    </html>
    """
  end

  # Private: Markdown helpers

  defp summary_header(summary) do
    summary |> Map.keys() |> Enum.map_join(" | ", &format_adapter/1)
  end

  defp summary_separator(summary) do
    summary |> Map.keys() |> Enum.map_join("|", fn _ -> "--------" end)
  end

  defp summary_rows(summary) do
    metrics = [
      {"Mean Latency (ms)", fn s -> format_number(s[:mean_latency_ms] || s.mean_latency_ms) end},
      {"P50 Latency (ms)", fn s -> format_number(s[:p50] || s.p50) end},
      {"P99 Latency (ms)", fn s -> format_number(s[:p99] || s.p99) end},
      {"Mean Tokens", fn s -> format_number(s[:mean_tokens] || s.mean_tokens) end},
      {"Mean Accuracy", fn s -> format_number(s[:mean_accuracy] || s.mean_accuracy) end},
      {"Pass Rate", fn s -> format_number(s[:pass_rate] || s.pass_rate) end}
    ]

    Enum.map_join(metrics, "\n", fn {label, extractor} ->
      values = summary |> Map.values() |> Enum.map_join(" | ", extractor)
      "| #{label} | #{values} |"
    end)
  end

  defp format_adapter(adapter) when is_atom(adapter), do: adapter |> Atom.to_string() |> format_adapter()
  defp format_adapter("agent_loop"), do: "Agent Loop"
  defp format_adapter("stack"), do: "Stack"
  defp format_adapter("baseline"), do: "Baseline"
  defp format_adapter(other), do: other

  defp format_number(n) when is_float(n), do: :erlang.float_to_binary(n, decimals: 2)
  defp format_number(n) when is_integer(n), do: Integer.to_string(n)
  defp format_number(_), do: "-"

  defp format_delta(n) when is_float(n) do
    sign = if n > 0, do: "+", else: ""
    "#{sign}#{:erlang.float_to_binary(n, decimals: 4)}"
  end

  defp format_delta(n) when is_integer(n), do: format_delta(n * 1.0)
  defp format_delta(_), do: "N/A"

  defp latency_interpretation(%{latency_delta_ms: d}) when d > 0, do: "Stack is #{format_number(d)}ms slower"
  defp latency_interpretation(%{latency_delta_ms: d}) when d < 0, do: "Stack is #{format_number(abs(d))}ms faster"
  defp latency_interpretation(_), do: "Comparable latency"

  defp token_interpretation(%{token_delta: d}) when d > 0, do: "Stack uses #{format_number(d)} more tokens"
  defp token_interpretation(%{token_delta: d}) when d < 0, do: "Stack uses #{format_number(abs(d))} fewer tokens"
  defp token_interpretation(_), do: "Comparable token usage"

  defp accuracy_interpretation(%{accuracy_delta: d}) when d > 0, do: "Stack is #{format_number(d)} more accurate"
  defp accuracy_interpretation(%{accuracy_delta: d}) when d < 0, do: "Stack is #{format_number(abs(d))} less accurate"
  defp accuracy_interpretation(_), do: "Comparable accuracy"

  defp pi_recommendation(%{pi_score: pi}) when pi > 0.1, do: "Stack is recommended: accuracy gain outweighs latency and token costs."
  defp pi_recommendation(%{pi_score: pi}) when pi < -0.1, do: "Agent loop is recommended: lower overhead with acceptable accuracy."
  defp pi_recommendation(_), do: "No clear winner: tradeoffs are balanced."

  defp generate_recommendations(summary, tradeoff) do
    lines = []

    lines =
      if (tradeoff[:pi_score] || tradeoff.pi_score) > 0 do
        lines ++ ["- Consider using the stack for accuracy-sensitive workloads"]
      else
        lines ++ ["- Consider using the agent loop for latency-sensitive workloads"]
      end

    agent_stats = Map.get(summary, :agent_loop)
    stack_stats = Map.get(summary, :stack)

    lines =
      if agent_stats && stack_stats do
        agent_pr = agent_stats[:pass_rate] || agent_stats.pass_rate
        stack_pr = stack_stats[:pass_rate] || stack_stats.pass_rate

        if stack_pr > agent_pr do
          lines ++ ["- Stack shows higher pass rate (#{format_number(stack_pr)} vs #{format_number(agent_pr)})"]
        else
          lines ++ ["- Agent loop shows higher pass rate (#{format_number(agent_pr)} vs #{format_number(stack_pr)})"]
        end
      else
        lines
      end

    Enum.join(lines, "\n")
  end

  # Private: HTML helpers

  defp summary_cards(summary) do
    Enum.map_join(summary, "\n", fn {adapter, stats} ->
      """
      <div class="card">
        <h3>#{format_adapter(adapter)}</h3>
        <div class="value">#{format_number(stats[:mean_latency_ms] || stats.mean_latency_ms)}ms</div>
        <div class="label">Mean Latency</div>
        <div class="value" style="font-size:1.5em;margin-top:10px">#{format_number(stats[:mean_tokens] || stats.mean_tokens)}</div>
        <div class="label">Mean Tokens</div>
        <div class="value" style="font-size:1.5em;margin-top:10px">#{format_number(stats[:mean_accuracy] || stats.mean_accuracy)}</div>
        <div class="label">Mean Accuracy</div>
      </div>
      """
    end)
  end

  defp tradeoff_rows_html(tradeoff) do
    latency_d = tradeoff[:latency_delta_ms] || tradeoff.latency_delta_ms
    token_d = tradeoff[:token_delta] || tradeoff.token_delta
    accuracy_d = tradeoff[:accuracy_delta] || tradeoff.accuracy_delta

    """
    <tr class="#{row_class(:lower, latency_d)}"><td>Latency</td><td>#{format_delta(latency_d)}ms</td><td>#{winner_label(:lower, latency_d)}</td></tr>
    <tr class="#{row_class(:lower, token_d)}"><td>Tokens</td><td>#{format_delta(token_d)}</td><td>#{winner_label(:lower, token_d)}</td></tr>
    <tr class="#{row_class(:higher, accuracy_d)}"><td>Accuracy</td><td>#{format_delta(accuracy_d)}</td><td>#{winner_label(:higher, accuracy_d)}</td></tr>
    """
  end

  defp detail_rows_html(summary) do
    Enum.map_join(summary, "\n", fn {adapter, stats} ->
      """
      <tr>
        <td>#{format_adapter(adapter)}</td>
        <td>#{format_number(stats[:mean_latency_ms] || stats.mean_latency_ms)}</td>
        <td>#{format_number(stats[:mean_tokens] || stats.mean_tokens)}</td>
        <td>#{format_number(stats[:mean_accuracy] || stats.mean_accuracy)}</td>
        <td>#{format_number(stats[:pass_rate] || stats.pass_rate)}</td>
      </tr>
      """
    end)
  end

  defp latency_svg_chart(summary) do
    adapters = Map.keys(summary)
    max_latency = summary |> Map.values() |> Enum.map(&((&1[:mean_latency_ms] || &1.mean_latency_ms) * 1.0)) |> Enum.max(fn -> 1.0 end)
    bar_width = 80
    chart_height = 200
    padding = 40

    bars =
      adapters
      |> Enum.with_index()
      |> Enum.map_join("\n", fn {adapter, i} ->
        stats = Map.get(summary, adapter)
        latency = (stats[:mean_latency_ms] || stats.mean_latency_ms) * 1.0
        height = if max_latency > 0, do: latency / max_latency * (chart_height - padding), else: 0
        x = padding + i * (bar_width + 20)
        y = chart_height - height
        color = adapter_color(adapter)

        """
        <rect x="#{x}" y="#{y}" width="#{bar_width}" height="#{height}" fill="#{color}" rx="4"/>
        <text x="#{x + bar_width / 2}" y="#{chart_height + 20}" text-anchor="middle" fill="currentColor" font-size="12">#{format_adapter(adapter)}</text>
        <text x="#{x + bar_width / 2}" y="#{y - 5}" text-anchor="middle" fill="currentColor" font-size="11">#{format_number(latency)}ms</text>
        """
      end)

    chart_width = padding + length(adapters) * (bar_width + 20) + padding

    """
    <svg viewBox="0 0 #{chart_width} #{chart_height + 40}" xmlns="http://www.w3.org/2000/svg">
    #{bars}
    </svg>
    """
  end

  defp adapter_color(:agent_loop), do: "#7dcfff"
  defp adapter_color(:stack), do: "#9ece6a"
  defp adapter_color(:baseline), do: "#e0af68"
  defp adapter_color(_), do: "#7aa2f7"

  defp row_class(:lower, delta) when delta > 10, do: "win-agent"
  defp row_class(:lower, delta) when delta < -10, do: "win-stack"
  defp row_class(:higher, delta) when delta > 0.05, do: "win-stack"
  defp row_class(:higher, delta) when delta < -0.05, do: "win-agent"
  defp row_class(_, _), do: "win-tie"

  defp winner_label(:lower, delta) when delta > 10, do: "Agent Loop"
  defp winner_label(:lower, delta) when delta < -10, do: "Stack"
  defp winner_label(:higher, delta) when delta > 0.05, do: "Stack"
  defp winner_label(:higher, delta) when delta < -0.05, do: "Agent Loop"
  defp winner_label(_, _), do: "Tie"
end
