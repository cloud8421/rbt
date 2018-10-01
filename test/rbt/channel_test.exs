defmodule Rbt.ChannelTest do
  use ExUnit.Case, async: true

  alias Rbt.{Conn, Channel}

  setup :start_conn

  test "open and close" do
    assert {:ok, channel} = Channel.open(__MODULE__)

    assert :ok == Channel.close(channel)
  end

  defp start_conn(_config) do
    {:ok, _pid} = Conn.start_link("amqp://guest:guest@localhost:5672/rbt-test", [], __MODULE__)

    :ok
  end
end
