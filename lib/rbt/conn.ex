defmodule Rbt.Conn do
  @behaviour :gen_statem

  alias Rbt.Conn.URI, as: ConnURI
  alias Rbt.Backoff

  @default_start_opts [
    retry_interval: 5000,
    heartbeat: 60,
    connection_timeout: 5000
  ]

  defstruct start_opts: @default_start_opts,
            backoff_intervals: Backoff.default_intervals(),
            uri: nil,
            conn: nil,
            mon_ref: nil

  @type url :: String.t()
  @type start_opts :: Keyword.t()

  @spec callback_mode :: :gen_statem.callback_mode()
  def callback_mode, do: :state_functions

  @spec start_link(url) :: :gen_statem.start_ret()
  def start_link(url) do
    start_link(url, @default_start_opts)
  end

  @spec start_link(url, start_opts) :: :gen_statem.start_ret()
  def start_link(uri, start_opts) do
    :gen_statem.start_link(__MODULE__, {uri, start_opts}, [])
  end

  @spec get(:gen_statem.server_ref()) :: {:ok, AMQP.Connection.t()} | {:error, :disconnected}
  def get(ref) do
    :gen_statem.call(ref, :get)
  end

  def init({uri, start_opts}) do
    case ConnURI.validate(uri) do
      :ok ->
        action = {:next_event, :internal, :try_connect}
        data = %__MODULE__{start_opts: start_opts, uri: uri}
        {:ok, :disconnected, data, action}

      {:error, reason} ->
        {:stop, {:invalid_uri, reason}}
    end
  end

  def disconnected(event_type, :try_connect, data)
      when event_type in [:internal, :timeout] do
    uri_options = Keyword.take(data.start_opts, [:heartbeat, :connection_timeout])
    uri_with_options = ConnURI.merge_options(data.uri, uri_options)

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
