defmodule Rbt.Conn do
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
  @type name :: atom | :gen_statem.server_name()

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

  @impl true
  @spec callback_mode :: :gen_statem.callback_mode()
  def callback_mode, do: :state_functions

  @spec start_link(url) :: :gen_statem.start_ret()
  def start_link(url) do
    start_link(url, @default_open_opts)
  end

  @spec start_link(url, open_opts) :: :gen_statem.start_ret()
  def start_link(uri, open_opts) do
    open_opts = Keyword.merge(@default_open_opts, open_opts)
    :gen_statem.start_link(__MODULE__, {uri, open_opts}, [])
  end

  @spec start_link(url, open_opts, name) :: :gen_statem.start_ret()
  def start_link(uri, open_opts, name) when is_atom(name) do
    start_link(uri, open_opts, {:local, name})
  end

  def start_link(uri, open_opts, name) do
    open_opts = Keyword.merge(@default_open_opts, open_opts)
    :gen_statem.start_link(name, __MODULE__, {uri, open_opts}, [])
  end

  @spec get(:gen_statem.server_ref()) :: {:ok, AMQP.Connection.t()} | {:error, :disconnected}
  def get(ref) do
    :gen_statem.call(ref, :get)
  end

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

  def disconnected(event_type, :try_connect, data)
      when event_type in [:internal, :timeout] do
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
        action = {:timeout, delay, :try_connect}
        {:next_state, :disconnected, %{new_data | conn: nil, mon_ref: nil}, action}
    end
  end

  def disconnected({:call, from}, :get, _data) do
    {:keep_state_and_data, {:reply, from, {:error, :disconnected}}}
  end

  def connected(:info, {:DOWN, ref, :process, pid, _reason}, data) do
    if data.mon_ref == ref and data.conn.pid == pid do
      {delay, new_data} = Backoff.next_interval(data)
      action = {:timeout, delay, :try_connect}
      {:next_state, :disconnected, %{new_data | conn: nil, mon_ref: nil}, action}
    else
      :keep_state_and_data
    end
  end

  def connected({:call, from}, :get, data) do
    {:keep_state_and_data, {:reply, from, {:ok, data.conn}}}
  end
end
