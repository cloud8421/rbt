defmodule Rbt.Consumer do
  @behaviour :gen_statem

  alias Rbt.{Channel, Backoff, Consumer.Deliver}

  @default_definitions %{
    exchange_name: nil,
    queue_name: nil,
    routing_keys: []
  }

  @default_config %{max_workers: 5, durable_objects: false, max_retries: :infinity}

  defstruct conn_ref: nil,
            channel: nil,
            definitions: @default_definitions,
            config: @default_config,
            consumer_tag: nil,
            handler: nil,
            backoff_intervals: Backoff.default_intervals(),
            instrumentation: Rbt.Instrumentation.NoOp

  ################################################################################
  ################################## PUBLIC API ##################################
  ################################################################################

  def start_link(conn_ref, handler), do: start_link(conn_ref, handler, handler.config())

  def start_link(conn_ref, handler, config) do
    definitions = Map.fetch!(config, :definitions)
    exchange_name = Map.fetch!(definitions, :exchange_name)
    queue_name = Map.fetch!(definitions, :queue_name)

    :gen_statem.start_link(
      via(exchange_name, queue_name),
      __MODULE__,
      {conn_ref, handler, config},
      []
    )
  end

  def cancel(exchange_name, queue_name) do
    :gen_statem.call(via(exchange_name, queue_name), :cancel)
  end

  def consume(exchange_name, queue_name) do
    :gen_statem.call(via(exchange_name, queue_name), :consume)
  end

  ################################################################################
  ################################## CALLBACKS ###################################
  ################################################################################

  def child_spec(opts) do
    conn_ref = Keyword.fetch!(opts, :conn_ref)
    handler = Keyword.fetch!(opts, :handler)
    config = Enum.into(opts, %{})

    %{
      id: opts,
      start: {__MODULE__, :start_link, [conn_ref, handler, config]},
      type: :worker,
      restart: :permanent,
      shutdown: 500
    }
  end

  def callback_mode, do: :handle_event_function

  def init({conn_ref, handler, opts}) do
    definitions = Map.fetch!(opts, :definitions)
    config = Map.take(opts, [:max_workers, :max_retries, :durable_objects])

    data = %__MODULE__{
      conn_ref: conn_ref,
      definitions: definitions,
      config: config,
      handler: handler
    }

    action = {:next_event, :internal, :try_declare}
    {:ok, :idle, data, action}
  end

  ################################################################################
  ############################### STATE CALLBACKS ################################
  ################################################################################

  # SETUP OBJECTS AND AUTO SUBSCRIPTION

  def handle_event(event_type, :try_declare, :idle, data)
      when event_type in [:internal, :timeout] do
    case Channel.open(data.conn_ref) do
      {:ok, channel} ->
        set_prefetch_count!(channel, data.config)
        Process.monitor(channel.pid)
        setup_infrastructure!(channel, data.definitions, data.config)
        action = {:next_event, :internal, :subscribe}

        new_data =
          data
          |> Backoff.reset!()
          |> Map.put(:channel, channel)

        {:next_state, :unsubscribed, new_data, action}

      _error ->
        {delay, new_data} = Backoff.next_interval(data)
        action = {:timeout, delay, :try_declare}
        {:keep_state, %{new_data | channel: nil}, action}
    end
  end

  def handle_event(:internal, :subscribe, :unsubscribed, data) do
    subscribe!(data.channel, data.definitions.queue_name)

    {:next_state, :subscribing, data}
  end

  # MESSAGE HANDLING

  def handle_event(:info, {:basic_deliver, payload, meta}, :subscribed, data) do
    handle_delivery!(payload, meta, data)
    :keep_state_and_data
  end

  def handle_event(:info, {:basic_deliver, _payload, meta}, _other_state, data) do
    reject_and_requeue!(data.channel, meta.delivery_tag)
    :keep_state_and_data
  end

  # MANUAL CANCEL

  def handle_event({:call, from}, :cancel, :subscribed, data) do
    unsubscribe!(data.channel, data.consumer_tag)
    action = {:reply, from, {:ok, :requested}}
    {:next_state, :canceling, data, action}
  end

  def handle_event({:call, from}, :cancel, :canceling, _data) do
    action = {:reply, from, {:error, :in_progress}}
    {:keep_state_and_data, action}
  end

  def handle_event({:call, from}, :cancel, :unsubscribed, _data) do
    action = {:reply, from, :ok}
    {:keep_state_and_data, action}
  end

  def handle_event({:call, from}, :cancel, _other_state, _data) do
    action = {:reply, from, {:error, :invalid}}
    {:keep_state_and_data, action}
  end

  # MANUAL CONSUME

  def handle_event({:call, from}, :consume, :unsubscribed, data) do
    subscribe!(data.channel, data.definitions.queue_name)
    action = {:reply, from, {:ok, :requested}}
    {:next_state, :subscribing, data, action}
  end

  def handle_event({:call, from}, :consume, :subscribing, _data) do
    action = {:reply, from, {:error, :in_progress}}
    {:keep_state_and_data, action}
  end

  def handle_event({:call, from}, :consume, :subscribed, _data) do
    action = {:reply, from, :ok}
    {:keep_state_and_data, action}
  end

  def handle_event({:call, from}, :consume, _other_state, _data) do
    action = {:reply, from, {:error, :invalid}}
    {:keep_state_and_data, action}
  end

  # SERVER SENT CONFIRMATIONS

  def handle_event(:info, {:basic_consume_ok, %{consumer_tag: consumer_tag}}, :subscribing, data) do
    instrument_consume_ok!(data)
    {:next_state, :subscribed, %{data | consumer_tag: consumer_tag}}
  end

  def handle_event(:info, {:basic_cancel_ok, %{consumer_tag: consumer_tag}}, :canceling, data) do
    if consumer_tag == data.consumer_tag do
      instrument_cancel_ok!(data)
      {:next_state, :unsubscribed, %{data | consumer_tag: nil}}
    else
      :keep_state_and_data
    end
  end

  ################################################################################
  ################################### PRIVATE ####################################
  ################################################################################

  defp via(exchange_name, queue_name) do
    {:via, Registry, {Registry.Rbt.Consumer, {exchange_name, queue_name}}}
  end

  defp retry_exchange_name(exchange_name), do: exchange_name <> "-retries"

  # AMQP operations

  defp set_prefetch_count!(channel, config) do
    max_workers = Map.get(config, :max_workers, @default_config.max_workers)
    :ok = AMQP.Basic.qos(channel, prefetch_count: max_workers)
  end

  defp setup_infrastructure!(channel, definitions, config) do
    declare_exchange!(channel, definitions.exchange_name, config)
    declare_exchange!(channel, retry_exchange_name(definitions.exchange_name), config)
    declare_queue!(channel, definitions.queue_name, config)

    bind_queue!(
      channel,
      definitions.queue_name,
      definitions.exchange_name,
      definitions.routing_keys
    )

    bind_queue!(channel, definitions.queue_name, retry_exchange_name(definitions.exchange_name), [
      definitions.queue_name
    ])
  end

  defp declare_exchange!(channel, exchange_name, config) do
    durable = Map.get(config, :durable_objects, @default_config.durable_objects)

    :ok = AMQP.Exchange.declare(channel, exchange_name, :topic, durable: durable)
  end

  defp declare_queue!(channel, queue_name, config) do
    durable = Map.get(config, :durable_objects, @default_config.durable_objects)

    {:ok, _queue_stats} = AMQP.Queue.declare(channel, queue_name, durable: durable)
  end

  defp bind_queue!(channel, queue_name, exchange_name, routing_keys) do
    Enum.each(routing_keys, fn rk ->
      AMQP.Queue.bind(channel, queue_name, exchange_name, routing_key: rk)
    end)
  end

  defp subscribe!(channel, queue_name) do
    {:ok, _consumer_tag} = AMQP.Basic.consume(channel, queue_name)
  end

  defp unsubscribe!(channel, consumer_tag) do
    {:ok, ^consumer_tag} = AMQP.Basic.cancel(channel, consumer_tag)
  end

  defp reject_and_requeue!(channel, delivery_tag) do
    AMQP.Basic.reject(channel, delivery_tag, requeue: true)
  end

  defp reject!(channel, delivery_tag) do
    AMQP.Basic.reject(channel, delivery_tag, requeue: false)
  end

  defp ack!(channel, delivery_tag) do
    AMQP.Basic.ack(channel, delivery_tag)
  end

  # MESSAGE HANDLING

  defp handle_delivery!(payload, meta, data) do
    case {data.config.max_retries, get_retry_count(meta)} do
      {:infinite, _retry_count} ->
        handle_with_infinite_retries(payload, meta, data)

      {max_retries, retry_count} when retry_count >= max_retries ->
        reject!(data.channel, meta.delivery_tag)

      {_max_retries, retry_count} ->
        handle_with_limited_retries(payload, meta, data, retry_count)
    end

    :keep_state_and_data
  end

  defp get_retry_count(meta) do
    {"retry_count", _, retry_count} =
      List.keyfind(meta.headers, "retry_count", 0, {"retry_count", :long, 0})

    retry_count
  end

  defp handle_with_infinite_retries(payload, meta, data) do
    case Deliver.handle(payload, meta, data) do
      :ok ->
        ack!(data.channel, meta.delivery_tag)

      {:error, _retry_policy, _reason} ->
        reject_and_requeue!(data.channel, meta.delivery_tag)
    end
  end

  defp handle_with_limited_retries(payload, meta, data, retry_count) do
    case Deliver.handle(payload, meta, data) do
      :ok ->
        ack!(data.channel, meta.delivery_tag)

      {:error, :retry, _reason} ->
        requeue_with_retry!(payload, meta, data, retry_count + 1)

      {:error, :no_retry, _reason} ->
        reject!(data.channel, meta.delivery_tag)
    end
  end

  defp requeue_with_retry!(payload, meta, data, retry_count) do
    %{exchange_name: exchange_name, queue_name: queue_name} = data.definitions

    opts = [
      persistent: data.config.durable_objects,
      headers: [retry_count: retry_count],
      content_type: meta.content_type
    ]

    ack!(data.channel, meta.delivery_tag)

    AMQP.Basic.publish(
      data.channel,
      retry_exchange_name(exchange_name),
      queue_name,
      payload,
      opts
    )
  end

  # INSTRUMENTATION

  defp instrument_consume_ok!(data) do
    %{exchange_name: exchange_name, queue_name: queue_name} = data.definitions
    data.instrumentation.on_consume(exchange_name, queue_name)
  end

  defp instrument_cancel_ok!(data) do
    %{exchange_name: exchange_name, queue_name: queue_name} = data.definitions
    data.instrumentation.on_cancel(exchange_name, queue_name)
  end
end
