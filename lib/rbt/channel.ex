defmodule Rbt.Channel do
  @moduledoc """
  This module includes functions to interact with channels.
  """
  alias Rbt.Conn

  def open(conn_name) do
    case Conn.get(conn_name) do
      {:ok, conn} -> AMQP.Channel.open(conn)
      error -> error
    end
  end

  def close(channel) do
    AMQP.Channel.close(channel)
  end
end
