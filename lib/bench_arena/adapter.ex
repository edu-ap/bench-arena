defmodule BenchArena.Adapter do
  @moduledoc """
  Behaviour for benchmark adapters. All adapters must implement execute/1.
  """

  alias BenchArena.Corpus.Question

  @callback execute(Question.t()) ::
              {:ok, %{answer: String.t(), tokens_in: integer(), tokens_out: integer()}}
              | {:error, reason :: term()}
end
