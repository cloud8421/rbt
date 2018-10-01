defmodule Rbt.Backoff do
  @moduledoc false

  @max_interval 30000
  @default_intervals [100, 500, 1000, 2000, 5000, 10000, @max_interval]

  @type intervals :: [pos_integer()]
  @type map_with_intervals :: %{
          required(:backoff_intervals) => intervals(),
          optional(any) => any()
        }

  def default_intervals, do: @default_intervals

  @spec reset!(map_with_intervals()) :: map_with_intervals()
  def reset!(state) do
    %{state | backoff_intervals: @default_intervals}
  end

  @spec next_interval(map_with_intervals()) :: {:ok, pos_integer(), map_with_intervals()}
  def next_interval(%{backoff_intervals: []}) do
    {:ok, @max_interval, [@max_interval]}
  end

  def next_interval(%{backoff_intervals: backoff_interval} = state) do
    {delay, new_backoff_interval} = get_delay(backoff_interval)
    {:ok, delay, %{state | backoff_intervals: new_backoff_interval}}
  end

  defp get_delay([delay]), do: {delay, [delay]}
  defp get_delay([delay | remaining]), do: {delay, remaining}
end
