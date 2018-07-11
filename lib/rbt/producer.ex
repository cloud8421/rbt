defmodule Rbt.Producer do
  @behaviour :gen_statem

  alias Rbt.{Channel, Backoff, Producer.Event}
  import Rbt.Registry.Producer, only: [via: 1]

  @default_config %{
    durable_objects: false
  }

  @config_keys Map.keys(@default_config)

  defstruct conn_ref: nil,
            mon_ref: nil,
            exchange_name: nil,
            config: @default_config,
            channel: nil,
            buffer: :queue.new(),
            backoff_intervals: Backoff.default_intervals(),
            instrumentation: Rbt.Instrumentation.NoOp.Producer

  ################################################################################
  ################################## PUBLIC API ##################################
  ################################################################################

  def start_link(conn_ref, opts) do
    exchange_name = Map.fetch!(opts, :exchange_name)

    :gen_statem.start_link(via(exchange_name), __MODULE__, {conn_ref, opts}, [])
  end

  def publish(exchange_name, topic, event_data, opts) do
    event_opts = [
      message_id: Keyword.get(opts, :message_id, Rbt.UUID.generate()),
      content_type: Keyword.fetch!(opts, :content_type),
      persistent: Keyword.get(opts, :persistent, false)
    ]

    event = Event.new(topic, event_data, event_opts)

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

  ################################################################################
  ################################## CALLBACKS ###################################
  ################################################################################

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
        {delay, new_data} = Backoff.next_interval(data)

        instrument_on_disconnect!(new_data)

        action = {:state_timeout, delay, :try_declare}
        {:keep_state, %{new_data | channel: nil, mon_ref: nil}, action}
    end
  end

  # PUBLISHING

  def handle_event({:call, from}, {:publish, event}, :buffering, data) do
    new_buffer = :queue.in(event, data.buffer)
    action = {:reply, from, :ok}

    {:keep_state, %{data | buffer: new_buffer}, action}
  end

  def handle_event({:call, from}, {:publish, event}, :active, data) do
    case publish_event(event, data.channel, data.exchange_name) do
      :closing ->
        instrument_publish_error!(data, event, :channel_closing, :queue.len(data.buffer))
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
          :closing ->
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

  ################################################################################
  ################################### PRIVATE ####################################
  ################################################################################

  defp declare_exchange!(channel, exchange_name, config) do
    durable = Map.get(config, :durable_objects, @default_config.durable_objects)

    :ok = AMQP.Exchange.declare(channel, exchange_name, :topic, durable: durable)
  end

  # PUBLISHING

  defp publish_event(event, channel, exchange_name) do
    content_type = Keyword.get(event.opts, :content_type)

    case Rbt.Data.encode(event.data, content_type) do
      {:ok, encoded} ->
        AMQP.Basic.publish(
          channel,
          exchange_name,
          event.topic,
          encoded,
          event.opts
        )

      error ->
        error
    end
  end

  # INSTRUMENTATION

  defp instrument_setup!(data) do
    data.instrumentation.setup(data.exchange_name)
  end

  defp instrument_teardown!(data) do
    data.instrumentation.teardown(data.exchange_name)
  end

  defp instrument_on_connect!(data) do
    data.instrumentation.on_connect(data.exchange_name)
  end

  defp instrument_on_disconnect!(data) do
    data.instrumentation.on_disconnect(data.exchange_name)
  end

  defp instrument_publish_ok!(data, event, buffer_size) do
    data.instrumentation.on_publish_ok(data.exchange_name, event, buffer_size)
  end

  defp instrument_publish_error!(data, event, error, buffer_size) do
    data.instrumentation.on_publish_ok(data.exchange_name, event, error, buffer_size)
  end

  defp instrument_queue!(data, event, buffer_size) do
    data.instrumentation.on_queue(data.exchange_name, event, buffer_size)
  end
end
