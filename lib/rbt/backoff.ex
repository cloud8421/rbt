defmodule Rbt.Backoff do
  @moduledoc """
  Implements a simple backoff management system compatible
  with any map or struct having a `:backoff_intervals` key.
  """

  @max_interval 30000
  @default_intervals [100, 500, 1000, 2000, 5000, 10000, @max_interval]

  @type intervals :: [pos_integer()]
  @type map_with_intervals :: %{
          required(:backoff_intervals) => intervals(),
          optional(any) => any()
        }

  @doc """
  Returns the series of intervals as a list.
  """
  @spec default_intervals() :: intervals()
  def default_intervals, do: @default_intervals

  @doc """
  Given a map with intervals, updates it to have intervals at their default values.

      iex> m = %{backoff_intervals: [], name: "example"}
      iex> Rbt.Backoff.reset!(m)
      %{backoff_intervals: [100, 500, 1000, 2000, 5000, 10000, 30000], name: "example"}
  """
  @spec reset!(map_with_intervals()) :: map_with_intervals()
  def reset!(state) do
    %{state | backoff_intervals: @default_intervals}
  end

  @doc """
  Given a map with intervals, returns the next interval and the updated map
  with the next intervals sequence.

      iex> m = %{backoff_intervals: [100, 500, 2000], name: "example"}
      iex> Rbt.Backoff.next_interval(m)
      {:ok, 100, %{backoff_intervals: [500, 2000], name: "example"}}
  """
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
