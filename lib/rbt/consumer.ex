defmodule Rbt.Consumer do
  @behaviour :gen_statem

  alias Rbt.{Channel, Backoff}

  @default_definitions %{
    exchange_name: nil,
    queue_name: nil,
    routing_keys: []
  }

  @default_config %{max_workers: 5, durable_objects: false}

  defstruct conn_ref: nil,
            channel: nil,
            definitions: @default_definitions,
            config: @default_config,
            consumer_tag: nil,
            handler: nil,
            backoff_intervals: Backoff.default_intervals()

  ## PUBLIC API

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

  ## CALLBACKS

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
    config = Map.take(opts, [:max_workers, :durable_objects])

    data = %__MODULE__{
      conn_ref: conn_ref,
      definitions: definitions,
      config: config,
      handler: handler
    }

    action = {:next_event, :internal, :try_declare}
    {:ok, :idle, data, action}
  end

  # STATE CALLBACKS

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

  def handle_event(:info, {:basic_consume_ok, %{consumer_tag: consumer_tag}}, :subscribing, data) do
    {:next_state, :subscribed, %{data | consumer_tag: consumer_tag}}
  end

  def handle_event(:info, {:basic_deliver, _payload, _meta}, :subscribed, _data) do
    :keep_state_and_data
  end

  # PRIVATE

  defp via(exchange_name, queue_name) do
    {:via, Registry, {Registry.Rbt.Consumer, {exchange_name, queue_name}}}
  end

  defp set_prefetch_count!(channel, config) do
    max_workers = Map.get(config, :max_workers, @default_config.max_workers)
    :ok = AMQP.Basic.qos(channel, prefetch_count: max_workers)
  end

  defp setup_infrastructure!(channel, definitions, config) do
    declare_exchange!(channel, definitions.exchange_name, config)
    declare_queue!(channel, definitions.queue_name, config)

    bind_queue!(
      channel,
      definitions.queue_name,
      definitions.exchange_name,
      definitions.routing_keys
    )
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
end
