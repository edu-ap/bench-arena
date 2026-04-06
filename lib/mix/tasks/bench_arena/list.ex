defmodule Mix.Tasks.BenchArena.List do
  @moduledoc """
  List all benchmark result files.

  ## Usage

      mix bench_arena.list

  Shows: run_id, date, question count, adapters used.
  """

  use Mix.Task

  @shortdoc "List bench-arena result files"

  @impl Mix.Task
  def run(_args) do
    output_dir = Application.get_env(:bench_arena, :results_dir, "bench_results")

    unless File.dir?(output_dir) do
      Mix.shell().info("No results directory found at #{output_dir}")
      return_empty()
    else
      json_files =
        output_dir
        |> File.ls!()
        |> Enum.filter(&String.ends_with?(&1, ".json"))
        |> Enum.sort()

      if json_files == [] do
        Mix.shell().info("No result files found in #{output_dir}/")
        return_empty()
      else
        # Header
        Mix.shell().info(
          String.pad_trailing("Run ID", 30) <>
            String.pad_trailing("Date", 14) <>
            String.pad_trailing("Questions", 12) <>
            "Adapters"
        )

        Mix.shell().info(String.duplicate("-", 80))

        Enum.each(json_files, fn file ->
          path = Path.join(output_dir, file)

          case parse_result_file(path) do
            {:ok, info} ->
              Mix.shell().info(
                String.pad_trailing(info.run_id, 30) <>
                  String.pad_trailing(info.date, 14) <>
                  String.pad_trailing("#{info.question_count}", 12) <>
                  Enum.join(info.adapters, ", ")
              )

            {:error, _} ->
              Mix.shell().info(
                String.pad_trailing(Path.basename(file, ".json"), 30) <>
                  String.pad_trailing("?", 14) <>
                  String.pad_trailing("?", 12) <>
                  "parse error"
              )
          end
        end)

        Mix.shell().info("\n#{length(json_files)} result file(s) found.")
      end
    end
  end

  defp return_empty, do: :ok

  defp parse_result_file(path) do
    case File.read(path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, data} when is_map(data) ->
            results = Map.get(data, "results", [])
            run_id = Map.get(data, "run_id", Path.basename(path, ".json"))

            adapters =
              results
              |> Enum.map(& &1["adapter"])
              |> Enum.uniq()
              |> Enum.sort()

            question_count =
              results
              |> Enum.map(& &1["question_id"])
              |> Enum.uniq()
              |> length()

            date = extract_date(results, path)

            {:ok,
             %{
               run_id: run_id,
               date: date,
               question_count: question_count,
               adapters: adapters
             }}

          {:ok, data} when is_list(data) ->
            adapters =
              data
              |> Enum.map(& &1["adapter"])
              |> Enum.uniq()
              |> Enum.sort()

            question_count =
              data
              |> Enum.map(& &1["question_id"])
              |> Enum.uniq()
              |> length()

            {:ok,
             %{
               run_id: Path.basename(path, ".json"),
               date: extract_date(data, path),
               question_count: question_count,
               adapters: adapters
             }}

          _ ->
            {:error, :invalid_json}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp extract_date(results, path) when is_list(results) do
    case Enum.find_value(results, & &1["timestamp"]) do
      nil ->
        case File.stat(path) do
          {:ok, %{mtime: mtime}} ->
            mtime |> NaiveDateTime.from_erl!() |> NaiveDateTime.to_date() |> Date.to_iso8601()

          _ ->
            "unknown"
        end

      timestamp ->
        String.slice(timestamp, 0, 10)
    end
  end
end
