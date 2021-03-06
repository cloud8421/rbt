defmodule Rbt.BackoffTest do
  use ExUnit.Case, async: true
  use PropCheck

  doctest Rbt.Backoff

  alias Rbt.Backoff

  property "delay is always between bounds" do
    forall intervals <- intervals(Backoff.default_intervals()) do
      state = %{backoff_intervals: intervals}

      {:ok, delay, new_state} = Backoff.next_interval(state)

      assert delay >= 100 and delay <= 30000
      assert Enum.count(new_state.backoff_intervals) >= 1
    end
  end

  def intervals(default_intervals) do
    max_bound = Enum.count(default_intervals)

    let n <- integer(0, max_bound) do
      Enum.take(default_intervals, -n)
    end
  end
end
