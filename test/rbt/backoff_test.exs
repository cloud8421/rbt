defmodule Rbt.BackoffTest do
  use ExUnit.Case
  use PropCheck

  alias Rbt.Backoff

  property "next interval is always between bounds" do
    max_bound = Enum.count(Backoff.default_intervals())

    forall n <- integer(1, max_bound) do
      intervals = Enum.take(Backoff.default_intervals(), -n)

      state = %{backoff_intervals: intervals}

      {delay, new_state} = Backoff.next_interval(state)

      assert delay >= 100 and delay <= 30000
      assert Enum.count(new_state.backoff_intervals) >= 1
    end
  end
end
