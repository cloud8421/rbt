defmodule Rbt.Channel do
  @moduledoc """
  This module includes functions to interact with channels.
  """

  alias Rbt.Conn

  @doc """
  Given a named connection, try to open a channel on it.
  """
  @spec open(Conn.name()) :: {:ok, AMQP.Channel.t()} | {:error, term()}
  def open(conn_name) do
    case Conn.get(conn_name) do
      {:ok, conn} -> AMQP.Channel.open(conn)
      error -> error
    end
  end

  @doc """
  Closes a given channel.
  """
  @spec close(AMQP.Channel.t()) :: :ok | {:error, AMQP.Basic.error()}
  def close(channel) do
    AMQP.Channel.close(channel)
  end
end
