defmodule Rbt.Producer do
  @behaviour :gen_statem

  alias Rbt.{Channel, Backoff, Producer.Event}
  import Rbt.Registry.Producer, only: [via: 1]

  @default_exchange_name ""

  @default_config %{
    durable_objects: false,
    exchange_type: :topic,
    instrumentation: Rbt.Instrumentation.NoOp.Producer
  }

  @config_keys Map.keys(@default_config)

  defstruct conn_ref: nil,
            mon_ref: nil,
            exchange_name: nil,
            config: @default_config,
            channel: nil,
            buffer: :queue.new(),
            backoff_intervals: Backoff.default_intervals()

  ################################################################################
  ################################## PUBLIC API ##################################
  ################################################################################

  def start_link(conn_ref, opts) do
    exchange_name = Map.fetch!(opts, :exchange_name)

    :gen_statem.start_link(via(exchange_name), __MODULE__, {conn_ref, opts}, [])
  end

  def publish(exchange_name, topic, event_data, opts) do
    message_id = Keyword.get(opts, :message_id, Rbt.UUID.generate())

    event_opts = [
      content_type: Keyword.fetch!(opts, :content_type),
      persistent: Keyword.get(opts, :persistent, false)
    ]

    event = Event.new(message_id, topic, event_data, event_opts)

    :gen_statem.call(via(exchange_name), {:publish, event})
  end

  def buffer_size(ref) when is_pid(ref) do
    :gen_statem.call(ref, :buffer_size)
  end

  def buffer_size(exchange_name) do
    :gen_statem.call(via(exchange_name), :buffer_size)
  end

  def buffer(ref) when is_pid(ref) do
    :gen_statem.call(ref, :buffer)
  end

  def buffer(exchange_name) do
    :gen_statem.call(via(exchange_name), :buffer)
  end

  def status(producer_ref) when is_pid(producer_ref) do
    :gen_statem.call(producer_ref, :status)
  end

  def status(exchange_name) do
    :gen_statem.call(via(exchange_name), :status)
  end

  def stop(producer_ref) when is_pid(producer_ref) do
    :gen_statem.call(producer_ref, :stop)
  end

  def stop(exchange_name) do
    :gen_statem.call(via(exchange_name), :stop)
  end

  ################################################################################
  ################################## CALLBACKS ###################################
  ################################################################################

  def child_spec(opts) do
    conn_ref = Keyword.fetch!(opts, :conn_ref)
    definitions = Keyword.get(opts, :definitions, %{})
    exchange_name = Map.fetch!(definitions, :exchange_name)

    %{
      id: {__MODULE__, exchange_name},
      start: {__MODULE__, :start_link, [conn_ref, definitions]},
      type: :worker,
      restart: :permanent,
      shutdown: 500
    }
  end

  def callback_mode, do: :handle_event_function

  def init({conn_ref, opts}) do
    exchange_name = Map.fetch!(opts, :exchange_name)
    config = Map.take(opts, @config_keys)

    data = %__MODULE__{
      conn_ref: conn_ref,
      exchange_name: exchange_name,
      config: Map.merge(@default_config, config)
    }

    instrument_setup!(data)

    Process.flag(:trap_exit, true)

    action = {:next_event, :internal, :try_declare}

    {:ok, :buffering, data, action}
  end

  def terminate(_reason, _state, data) do
    instrument_teardown!(data)

    if data.channel do
      AMQP.Channel.close(data.channel)
    end
  end

  ################################################################################
  ############################### STATE CALLBACKS ################################
  ################################################################################

  # SETUP OBJECTS

  def handle_event(event_type, :try_declare, :buffering, data)
      when event_type in [:internal, :state_timeout] do
    case Channel.open(data.conn_ref) do
      {:ok, channel} ->
        mon_ref = Process.monitor(channel.pid)

        declare_exchange!(channel, data.exchange_name, data.config)

        new_data =
          data
          |> Backoff.reset!()
          |> Map.put(:mon_ref, mon_ref)
          |> Map.put(:channel, channel)

        instrument_on_connect!(new_data)

        action = {:next_event, :internal, :flush_buffer}

        {:next_state, :active, new_data, action}

      _error ->
        {:ok, delay, new_data} = Backoff.next_interval(data)

        instrument_on_disconnect!(new_data)

        action = {:state_timeout, delay, :try_declare}
        {:keep_state, %{new_data | channel: nil, mon_ref: nil}, action}
    end
  end

  # PUBLISHING

  def handle_event({:call, from}, {:publish, event}, :buffering, data) do
    new_buffer = :queue.in(event, data.buffer)

    instrument_queue!(data, event, :queue.len(new_buffer))
    action = {:reply, from, :ok}

    {:keep_state, %{data | buffer: new_buffer}, action}
  end

  def handle_event({:call, from}, {:publish, event}, :active, data) do
    case publish_event(event, data.channel, data.exchange_name) do
      {:error, :closing} ->
        instrument_publish_error!(data, event, :channel_closing, :queue.len(data.buffer))
        actions = [{:next_event, :internal, {:queue, event}}, {:reply, from, :ok}]
        {:keep_state_and_data, actions}

      {:error, :blocked} ->
        instrument_publish_error!(data, event, :channel_blocked, :queue.len(data.buffer))
        actions = [{:next_event, :internal, {:queue, event}}, {:reply, from, :ok}]
        {:keep_state_and_data, actions}

      {:error, :unsupported_content_type} = error ->
        instrument_publish_error!(data, event, :unsupported_content_type, :queue.len(data.buffer))
        action = {:reply, from, error}
        {:keep_state_and_data, action}

      _success ->
        instrument_publish_ok!(data, event, :queue.len(data.buffer))
        action = {:reply, from, :ok}
        {:keep_state_and_data, action}
    end
  end

  def handle_event(:internal, {:queue, event}, _state, data) do
    new_buffer = :queue.in(event, data.buffer)

    instrument_queue!(data, event, :queue.len(new_buffer))

    {:keep_state, %{data | buffer: new_buffer}}
  end

  def handle_event(:internal, :flush_buffer, :active, data) do
    case :queue.out(data.buffer) do
      {:empty, _queue} ->
        :keep_state_and_data

      {{:value, event}, new_buffer} ->
        case publish_event(event, data.channel, data.exchange_name) do
          {:error, :closing} ->
            instrument_publish_error!(data, event, :channel_closing, :queue.len(data.buffer))
            :keep_state_and_data

          {:error, :unsupported_content_type} ->
            instrument_publish_error!(
              data,
              event,
              :unsupported_content_type,
              :queue.len(data.buffer)
            )

            action = {:next_event, :internal, :flush_buffer}
            {:keep_state, %{data | buffer: new_buffer}, action}

          _success ->
            instrument_publish_ok!(data, event, :queue.len(data.buffer))
            action = {:next_event, :internal, :flush_buffer}
            {:keep_state, %{data | buffer: new_buffer}, action}
        end
    end
  end

  # INTROSPECTION

  def handle_event({:call, from}, :buffer_size, _state, data) do
    {:keep_state_and_data, {:reply, from, :queue.len(data.buffer)}}
  end

  def handle_event({:call, from}, :buffer, _state, data) do
    {:keep_state_and_data, {:reply, from, :queue.to_list(data.buffer)}}
  end

  # RECONNECTION

  def handle_event(:info, {:DOWN, ref, :process, pid, _reason}, _state, data) do
    if data.mon_ref == ref and data.channel.pid == pid do
      instrument_on_disconnect!(data)
      action = {:next_event, :internal, :try_declare}
      {:next_state, :buffering, %{data | channel: nil, mon_ref: nil}, action}
    else
      :keep_state_and_data
    end
  end

  # STATUS

  def handle_event({:call, from}, :status, state, data) do
    reply = %{state: state, data: data}
    action = {:reply, from, reply}
    {:keep_state_and_data, action}
  end

  # STOP

  def handle_event({:call, from}, :stop, _state, _data) do
    {:stop_and_reply, :normal, {:reply, from, :ok}}
  end

  ################################################################################
  ################################### PRIVATE ####################################
  ################################################################################

  defp declare_exchange!(_channel, :default, _config), do: :ok

  defp declare_exchange!(channel, exchange_name, config) do
    durable = Map.fetch!(config, :durable_objects)

    :ok = AMQP.Exchange.declare(channel, exchange_name, config.exchange_type, durable: durable)
  end

  # PUBLISHING

  defp publish_event(event, channel, exchange_name) do
    content_type = Keyword.get(event.opts, :content_type)

    case Rbt.Data.encode(event.data, content_type) do
      {:ok, encoded} ->
        opts = Keyword.put(event.opts, :message_id, event.message_id)

        AMQP.Basic.publish(
          channel,
          normalize_exchange_name(exchange_name),
          event.topic,
          encoded,
          opts
        )

      error ->
        error
    end
  end

  defp normalize_exchange_name(:default), do: @default_exchange_name
  defp normalize_exchange_name(name), do: name

  # INSTRUMENTATION

  defp instrument_setup!(data) do
    data.config.instrumentation.setup(data.exchange_name)
  end

  defp instrument_teardown!(data) do
    data.config.instrumentation.teardown(data.exchange_name)
  end

  defp instrument_on_connect!(data) do
    data.config.instrumentation.on_connect(data.exchange_name)
  end

  defp instrument_on_disconnect!(data) do
    data.config.instrumentation.on_disconnect(data.exchange_name)
  end

  defp instrument_publish_ok!(data, event, buffer_size) do
    data.config.instrumentation.on_publish_ok(data.exchange_name, event, buffer_size)
  end

  defp instrument_publish_error!(data, event, error, buffer_size) do
    data.config.instrumentation.on_publish_ok(data.exchange_name, event, error, buffer_size)
  end

  defp instrument_queue!(data, event, buffer_size) do
    data.config.instrumentation.on_queue(data.exchange_name, event, buffer_size)
  end
end
