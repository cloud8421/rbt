defmodule Rbt.Channel do
  alias Rbt.Conn

  def open(conn_name) do
    try do
      case Conn.get(conn_name) do
        {:ok, conn} -> AMQP.Channel.open(conn)
        error -> error
      end
    catch
      e ->
        {:error, e}

      _exit, e ->
        {:error, e}
    end
  end
end
