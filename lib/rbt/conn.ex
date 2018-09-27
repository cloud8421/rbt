defmodule Rbt.Conn do
  @moduledoc """
  This module implements a state machine that starts
  and monitors a named connection which gets automatically
  re-estabilished in case of issues.

  Reconnection attempts implement a backoff logic.
  """

  @behaviour :gen_statem

  alias Rbt.Conn.URI, as: ConnURI
  alias Rbt.Backoff

  @default_open_opts [
    heartbeat: 60,
    connection_timeout: 5000
  ]

  defstruct open_opts: @default_open_opts,
            backoff_intervals: Backoff.default_intervals(),
            uri: nil,
            conn: nil,
            mon_ref: nil

  @type url :: String.t()
  @type open_opts :: Keyword.t()
  # compatible with gen_statem
  @type name :: GenServer.name() | {:local, atom()}
  # compatible with gen_statem
  @type server_ref :: GenServer.server()
  @type start_ret :: {:ok, pid()} | {:error, term()}

  @doc """
  Implements a child specification suitable for use
  as a worker in a supervision tree.

      {Rbt.Conn, uri: "amqp://", name: :my_conn, open_opts: [heartbeat: 30_000]}

  The last parameter, `open_opts`, defaults to a `[]` and gets passed directly to
  `AMQP.Connection.open/1`.
  """
  def child_spec(opts) do
    uri = Keyword.fetch!(opts, :uri)
    name = Keyword.fetch!(opts, :name)
    open_opts = Keyword.get(opts, :open_opts, [])

    %{
      id: {__MODULE__, name},
      start: {__MODULE__, :start_link, [uri, open_opts, name]},
      type: :worker,
      restart: :permanent,
      shutdown: 500
    }
  end

  @doc false
  @impl true
  def callback_mode, do: :state_functions

  @doc """
  Starts a connection given just a url: the connection is not named, uses default options.
  """
  @spec start_link(url) :: start_ret()
  def start_link(url) do
    start_link(url, @default_open_opts)
  end

  @doc """
  Starts a connection given a url and open options: the connection is not named.
  """
  @spec start_link(url, open_opts) :: start_ret()
  def start_link(uri, open_opts) do
    open_opts = Keyword.merge(@default_open_opts, open_opts)
    :gen_statem.start_link(__MODULE__, {uri, open_opts}, [])
  end

  @doc """
  Starts a connection given url, open options and name.
  """
  @spec start_link(url, open_opts, name) :: start_ret()
  def start_link(uri, open_opts, name) when is_atom(name) do
    start_link(uri, open_opts, {:local, name})
  end

  def start_link(uri, open_opts, name) do
    open_opts = Keyword.merge(@default_open_opts, open_opts)
    :gen_statem.start_link(name, __MODULE__, {uri, open_opts}, [])
  end

  @doc """
  Returns a `AMQP.Connection` struct given a connection name or pid.
  """
  @spec get(server_ref()) ::
          {:ok, AMQP.Connection.t()} | {:error, :disconnected} | {:error, :non_existent}
  def get(ref) do
    try do
      :gen_statem.call(ref, :get, 3000)
    catch
      _exit, {type, _reason} when type in [:noproc, :normal] ->
        {:error, :non_existent}
    end
  end

  @doc """
  Closes a connection given a connection name or pid.
  """
  @spec close(server_ref()) :: :ok
  def close(ref) do
    :gen_statem.call(ref, :close)
  end

  @doc false
  @impl true
  def init({uri, open_opts}) do
    case ConnURI.validate(uri) do
      :ok ->
        action = {:next_event, :internal, :try_connect}
        data = %__MODULE__{open_opts: open_opts, uri: uri}
        {:ok, :disconnected, data, action}

      {:error, reason} ->
        {:stop, {:invalid_uri, reason}}
    end
  end

  @doc false
  def disconnected(event_type, :try_connect, data)
      when event_type in [:internal, :state_timeout] do
    uri_with_options = ConnURI.merge_options(data.uri, data.open_opts)

    case AMQP.Connection.open(uri_with_options) do
      {:ok, conn} ->
        mon_ref = Process.monitor(conn.pid)

        new_data =
          data
          |> Backoff.reset!()
          |> Map.put(:conn, conn)
          |> Map.put(:mon_ref, mon_ref)

        {:next_state, :connected, new_data}

      _error ->
        # TODO: pass failure to diagnostics
        {delay, new_data} = Backoff.next_interval(data)
        action = {:state_timeout, delay, :try_connect}
        {:next_state, :disconnected, %{new_data | conn: nil, mon_ref: nil}, action}
    end
  end

  @doc false
  def disconnected({:call, from}, :get, _data) do
    {:keep_state_and_data, {:reply, from, {:error, :disconnected}}}
  end

  def disconnected({:call, from}, :close, _data) do
    {:stop_and_reply, :normal, {:reply, from, :ok}}
  end

  @doc false
  def connected(:info, {:DOWN, ref, :process, pid, _reason}, data) do
    if data.mon_ref == ref and data.conn.pid == pid do
      {delay, new_data} = Backoff.next_interval(data)
      action = {:state_timeout, delay, :try_connect}
      {:next_state, :disconnected, %{new_data | conn: nil, mon_ref: nil}, action}
    else
      :keep_state_and_data
    end
  end

  def connected({:call, from}, :get, data) do
    {:keep_state_and_data, {:reply, from, {:ok, data.conn}}}
  end

  def connected({:call, from}, :close, data) do
    AMQP.Connection.close(data.conn)
    {:stop_and_reply, :normal, {:reply, from, :ok}}
  end
end
