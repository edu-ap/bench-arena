# Benchee benchmark script for BenchArena
# Run with: mix run bench/arena_bench.exs

alias BenchArena.{Corpus, Runner}

# Load a sample of questions for benchmarking
questions = Corpus.sample(1, 3)

if questions == [] do
  IO.puts("No questions loaded. Ensure priv/corpus/ files exist.")
else
  question = hd(questions)

  Benchee.run(
    %{
      "baseline_adapter" => fn ->
        Runner.run_question(question, :baseline)
      end
    },
    time: 5,
    memory_time: 2,
    warmup: 1,
    formatters: [
      Benchee.Formatters.Console
    ]
  )
end
