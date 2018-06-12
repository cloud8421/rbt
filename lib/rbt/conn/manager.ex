defmodule Rbt.Conn.Manager do
  use Supervisor

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    Supervisor.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    uri = Keyword.fetch!(opts, :uri)
    conn_names = Keyword.get(opts, :conn_names, [])
    conn_opts = Keyword.get(opts, :conn_opts, [])

    children =
      Enum.map(conn_names, fn conn_name ->
        {Rbt.Conn, name: conn_name, uri: uri, open_opts: conn_opts}
      end)

    Supervisor.init(children, strategy: :one_for_one)
  end
end
