defmodule BenchArena.Leaderboard do
  @moduledoc """
  Loader for publicly-attested benchmark scores imported from industry leaderboards.
  These are used exclusively for adapters that cannot be run locally (missing credentials).
  NEVER fabricate scores — only load from priv/leaderboard/public_scores.json.
  """

  @scores_path "priv/leaderboard/public_scores.json"

  @spec scores_for(String.t()) :: map()
  def scores_for(adapter_id) do
    all_scores()
    |> Map.get(to_string(adapter_id), %{})
  end

  @spec all_scores() :: map()
  def all_scores do
    path = scores_path()

    case File.read(path) do
      {:ok, content} -> Jason.decode!(content)
      {:error, _} -> %{}
    end
  end

  @spec benchmark_names() :: [String.t()]
  def benchmark_names do
    all_scores()
    |> Map.values()
    |> Enum.flat_map(&Map.keys/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp scores_path do
    case :code.priv_dir(:bench_arena) do
      {:error, _} -> @scores_path
      dir -> Path.join(to_string(dir), "leaderboard/public_scores.json")
    end
  end
end
