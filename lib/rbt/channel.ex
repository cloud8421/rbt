defmodule Rbt.Channel do
  alias Rbt.Conn

  def open(conn_name) do
    case Conn.get(conn_name) do
      {:ok, conn} -> AMQP.Channel.open(conn)
      error -> error
    end
  end
end
