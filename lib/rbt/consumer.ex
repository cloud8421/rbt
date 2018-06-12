defmodule Rbt.Consumer do
  @behaviour :gen_statem

  alias Rbt.{Channel, Backoff}

  defstruct conn_ref: nil,
            channel: nil,
            consumer_tag: nil,
            exchange_name: nil,
            queue_name: nil,
            config: %{},
            handler: nil,
            backoff_intervals: Backoff.default_intervals()

  @default_max_workers 5

  def child_spec(opts) do
    conn_ref = Keyword.fetch!(opts, :conn_ref)
    handler = Keyword.fetch!(opts, :handler)
    consumer_opts = Keyword.fetch!(opts, :consumer_opts)

    %{
      id: opts,
      start: {__MODULE__, :start_link, [conn_ref, handler, consumer_opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 500
    }
  end

  def callback_mode, do: :state_functions

  def start_link(conn_ref, handler), do: start_link(conn_ref, handler, handler.config())

  def start_link(conn_ref, handler, config) do
    :gen_statem.start_link(__MODULE__, {conn_ref, handler, config}, [])
  end

  def init({conn_ref, handler, config}) do
    exchange_name = Map.fetch!(config, :exchange_name)
    queue_name = Map.fetch!(config, :queue_name)

    data = %__MODULE__{
      conn_ref: conn_ref,
      exchange_name: exchange_name,
      queue_name: queue_name,
      config: config,
      handler: handler
    }

    action = {:next_event, :internal, :try_declare}
    {:ok, :idle, data, action}
  end

  def idle(event_type, :try_declare, data)
      when event_type in [:internal, :timeout] do
    case Channel.open(data.conn_ref) do
      {:ok, channel} ->
        set_prefetch_count!(channel, data.config)
        Process.monitor(channel.pid)
        setup_infrastructure!(channel, data)
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

  def unsubscribed(:internal, :subscribe, data) do
    subscribe!(data.channel, data.queue_name)

    {:next_state, :subscribing, data}
  end

  def subscribing(:info, {:basic_consume_ok, %{consumer_tag: consumer_tag}}, data) do
    {:next_state, :subscribed, %{data | consumer_tag: consumer_tag}}
  end

  def subscribed(:info, {:basic_deliver, _payload, _meta}, _data) do
    :keep_state_and_data
  end

  defp set_prefetch_count!(channel, config) do
    max_workers = Map.get(config, :max_workers, @default_max_workers)
    :ok = AMQP.Basic.qos(channel, prefetch_count: max_workers)
  end

  defp setup_infrastructure!(channel, data) do
    declare_exchange!(channel, data.exchange_name, data.config)
    declare_queue!(channel, data.queue_name, data.config)
    bind_queue!(channel, data.queue_name, data.exchange_name, data.config)
  end

  defp declare_exchange!(channel, exchange_name, config) do
    durable = Map.get(config, :durable_objects?, false)
    :ok = AMQP.Exchange.declare(channel, exchange_name, :topic, durable: durable)
  end

  defp declare_queue!(channel, queue_name, config) do
    durable = Map.get(config, :durable_objects?, false)
    {:ok, _queue_stats} = AMQP.Queue.declare(channel, queue_name, durable: durable)
  end

  defp bind_queue!(channel, queue_name, exchange_name, config) do
    routing_keys = Map.get(config, :routing_keys, [])

    Enum.each(routing_keys, fn rk ->
      AMQP.Queue.bind(channel, queue_name, exchange_name, routing_key: rk)
    end)
  end

  defp subscribe!(channel, queue_name) do
    {:ok, _consumer_tag} = AMQP.Basic.consume(channel, queue_name)
  end
end
