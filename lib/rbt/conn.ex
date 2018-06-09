defmodule Rbt.Conn do
  @behaviour :gen_statem

  @default_start_opts [
    # TODO: exponential backoff with reset
    retry_interval: 5000,
    heartbeat: 60,
    connection_timeout: 5000
  ]

  defstruct start_opts: @default_start_opts,
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
    case :amqp_uri.parse(uri) do
      {:ok, _params} ->
        action = {:next_event, :internal, :try_connect}
        data = %__MODULE__{start_opts: start_opts, uri: uri}
        {:ok, :disconnected, data, action}

      {:error, {reason, ^uri}} ->
        {:stop, {:invalid_uri, reason}}
    end
  end

  def disconnected(event_type, :try_connect, data)
      when event_type in [:internal, :timeout] do
    uri_options = Keyword.take(data.start_opts, [:heartbeat, :connection_timeout])
    uri_with_options = build_connection_uri(data.uri, uri_options)

    case AMQP.Connection.open(uri_with_options) do
      {:ok, conn} ->
        mon_ref = Process.monitor(conn.pid)
        {:next_state, :connected, %{data | conn: conn, mon_ref: mon_ref}}

      _error ->
        # TODO: pass failure to diagnostics
        {:next_state, :disconnected, data}
    end
  end

  def disconnected({:call, from}, :get, _data) do
    {:keep_state_and_data, {:reply, from, {:error, :disconnected}}}
  end

  def connected(:info, {:DOWN, ref, :process, pid, _reason}, data) do
    if data.mon_ref == ref and data.conn == pid do
      retry_interval = Keyword.get(data.start_opts, :retry_interval)
      action = {:timeout, retry_interval, :try_connect}
      {:next_state, :disconnected, %{data | conn: nil, mon_ref: nil}, action}
    else
      :keep_state_and_data
    end
  end

  def connected({:call, from}, :get, data) do
    {:keep_state_and_data, {:reply, from, {:ok, data.conn}}}
  end

  defp build_connection_uri(base_uri, uri_opts) do
    uri = URI.parse(base_uri)

    final_query =
      case uri.query do
        nil ->
          uri_opts

        options ->
          URI.decode_query(options, uri_opts)
      end

    uri
    |> Map.put(:query, URI.encode_query(final_query))
    |> URI.to_string()
  end
end
