defmodule BenchArena.ScorerTest do
  use ExUnit.Case, async: true

  alias BenchArena.Scorer

  import BenchArena.TestHelpers

  describe "exact_match/2" do
    test "returns 1.0 for identical strings" do
      assert Scorer.exact_match("hello", "hello") == 1.0
    end

    test "returns 1.0 for case-insensitive match" do
      assert Scorer.exact_match("Hello World", "hello world") == 1.0
    end

    test "returns 1.0 after trimming whitespace" do
      assert Scorer.exact_match("  hello  ", "hello") == 1.0
    end

    test "returns 0.0 for different strings" do
      assert Scorer.exact_match("hello", "world") == 0.0
    end

    test "normalizes punctuation" do
      assert Scorer.exact_match("3 bits.", "3 bits") == 1.0
    end

    test "normalizes multiple spaces" do
      assert Scorer.exact_match("3   bits", "3 bits") == 1.0
    end

    test "returns 0.0 for empty vs non-empty" do
      assert Scorer.exact_match("", "hello") == 0.0
    end

    test "returns 1.0 for both empty" do
      assert Scorer.exact_match("", "") == 1.0
    end
  end

  describe "semantic_score/2" do
    test "returns 1.0 for identical strings" do
      assert Scorer.semantic_score("hello world", "hello world") == 1.0
    end

    test "returns high score for similar strings" do
      score = Scorer.semantic_score("the quick brown fox", "the quick brown dog")
      assert score > 0.5
    end

    test "returns low score for dissimilar strings" do
      score = Scorer.semantic_score("completely different text", "nothing in common here")
      assert score < 0.5
    end

    test "returns 0.0 for no overlap" do
      assert Scorer.semantic_score("aaa bbb ccc", "xxx yyy zzz") == 0.0
    end

    test "is case insensitive" do
      assert Scorer.semantic_score("Hello World", "hello world") == 1.0
    end

    test "handles empty strings" do
      assert Scorer.semantic_score("", "") == 1.0
    end

    test "handles one empty string" do
      assert Scorer.semantic_score("", "hello") == 0.0
    end

    test "computes Jaccard correctly for known overlap" do
      # "a b c" vs "b c d" -> intersection={b,c}=2, union={a,b,c,d}=4 -> 0.5
      assert Scorer.semantic_score("a b c", "b c d") == 0.5
    end

    test "ignores punctuation in semantic scoring" do
      score = Scorer.semantic_score("hello, world!", "hello world")
      assert score == 1.0
    end
  end

  describe "rubric_score/2" do
    test "returns 0.0 for nil rubric" do
      assert Scorer.rubric_score("any answer", nil) == 0.0
    end

    test "returns 0.0 for empty criteria" do
      assert Scorer.rubric_score("answer", %{"criteria" => [], "max_score" => 0}) == 0.0
    end

    test "scores based on keyword presence" do
      rubric = %{"criteria" => ["hello", "world"], "max_score" => 2}
      assert Scorer.rubric_score("hello world", rubric) == 1.0
    end

    test "partial score for partial match" do
      rubric = %{"criteria" => ["hello", "world", "foo", "bar"], "max_score" => 4}
      assert Scorer.rubric_score("hello world", rubric) == 0.5
    end

    test "zero score when no criteria matched" do
      rubric = %{"criteria" => ["xyz", "abc"], "max_score" => 2}
      assert Scorer.rubric_score("hello world", rubric) == 0.0
    end

    test "is case insensitive" do
      rubric = %{"criteria" => ["Hello", "World"], "max_score" => 2}
      assert Scorer.rubric_score("HELLO WORLD", rubric) == 1.0
    end

    test "handles map criteria with keyword field" do
      rubric = %{"criteria" => [%{"keyword" => "kl_divergence"}, %{"keyword" => "reduce"}], "max_score" => 2}
      assert Scorer.rubric_score("kl_divergence with reduce", rubric) == 1.0
    end
  end

  describe "score/2" do
    test "dispatches to exact_match" do
      question = sample_question(%{scoring_method: :exact_match, reference_answer: "4"})
      assert Scorer.score("4", question) == 1.0
    end

    test "dispatches to semantic" do
      question = sample_question(%{scoring_method: :semantic, reference_answer: "hello world"})
      score = Scorer.score("hello world", question)
      assert score == 1.0
    end

    test "dispatches to rubric" do
      question = sample_rubric_question()
      score = Scorer.score("this kl_divergence uses reduce and log for probability", question)
      assert score == 1.0
    end
  end

  describe "exact_match/2 MCQ extraction" do
    test "extracts bold letter from natural language answer" do
      assert Scorer.exact_match("The answer is **B** because...", "B") == 1.0
    end

    test "extracts bold letter with closing paren" do
      assert Scorer.exact_match("**B)** is the correct choice", "B") == 1.0
    end

    test "extracts letter from 'answer is X' pattern" do
      assert Scorer.exact_match("The correct answer is C based on the analysis", "C") == 1.0
    end

    test "extracts letter from 'option X' pattern" do
      assert Scorer.exact_match("I would choose option D", "D") == 1.0
    end

    test "extracts leading letter with paren" do
      assert Scorer.exact_match("A) This is the answer", "A") == 1.0
    end

    test "returns 0.0 for wrong MCQ letter" do
      assert Scorer.exact_match("The answer is **B**", "C") == 0.0
    end

    test "returns 0.0 when no letter can be extracted" do
      assert Scorer.exact_match("I'm not sure about this question", "A") == 0.0
    end

    test "handles single letter reference that matches directly" do
      assert Scorer.exact_match("B", "B") == 1.0
    end
  end

  describe "exact_match/2 AIME integer extraction" do
    test "extracts bold integer from answer" do
      assert Scorer.exact_match("The answer is **143**.", "143") == 1.0
    end

    test "extracts standalone integer" do
      assert Scorer.exact_match("After calculation, the result is 42.", "42") == 1.0
    end

    test "returns 0.0 for wrong integer" do
      assert Scorer.exact_match("The answer is **143**.", "144") == 0.0
    end

    test "extracts single digit" do
      assert Scorer.exact_match("The answer is 7", "7") == 1.0
    end

    test "extracts zero" do
      assert Scorer.exact_match("The result is **0**", "0") == 1.0
    end

    test "handles integer reference that matches directly" do
      assert Scorer.exact_match("42", "42") == 1.0
    end
  end

  describe "batch_score/1" do
    test "scores multiple pairs" do
      q1 = sample_question(%{reference_answer: "4", scoring_method: :exact_match})
      q2 = sample_question(%{reference_answer: "hello", scoring_method: :exact_match})

      scores = Scorer.batch_score([{"4", q1}, {"world", q2}])
      assert scores == [1.0, 0.0]
    end

    test "handles empty list" do
      assert Scorer.batch_score([]) == []
    end
  end

  describe "calibration/1" do
    test "returns zero stats for empty list" do
      cal = Scorer.calibration([])
      assert cal.mean_score == 0.0
      assert cal.count == 0
    end

    test "computes mean score" do
      cal = Scorer.calibration([1.0, 0.0, 0.5])
      assert cal.mean_score == 0.5
      assert cal.count == 3
    end

    test "computes score distribution" do
      cal = Scorer.calibration([1.0, 0.95, 0.5, 0.2])
      assert is_map(cal.score_distribution)
      assert Map.has_key?(cal.score_distribution, "0.9-1.0")
    end
  end
end
