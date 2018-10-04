defmodule Rbt.Consumer do
  @moduledoc """
  Defines a consumer process, which will:

  - open a channel with the RabbitMQ server
  - enforce controlled consumption via the usage of the `prefetch_count`
    channel property (see the Capacity Planning section for more details)
  - ensure parallelized consumption via usage of supervised tasks
  - (optionally) declare its own topology (exchange, queue and binding, see the
    Topology section for more details)
  - (optionally) support retry and permanent failure management (see the Retry
    and Failure section for more details)

  #### Topology

  A `Rbt.Consumer` worker is able to define and create the topology needed to
  support its configuration, however it won't do that by default, requiring you
  to explicitly pass `create_infrastructure: true` when started to enable that.

  This means that it's up to the developer to manage the lifetime of the queue
  referenced in the configuration.

  With `create_infrastructure: true`, the consumer will create:

  - a topic exchange (the "source" exchange)
  - a topic exchange with the same name and `-retries` suffix (the "retries" exchange)
  - a dedicated queue
  - bindings between each exchange and the queue according to the routing keys specified
    in the configuration

  In addition, if the consumer is setup with `forward_failures: true`, a third
  exchange with the same name and `-errors` suffix (the "failures" exchange)
  will be created.

  For safety reasons, RabbitMQ doesn't allow re-declaration of the same object
  with different properties (e.g. re-declaring a queue with a different
  `durable` flag). `Rbt.Consumer` follows the same idea, pushing the design towards
  immutable queues which would need to be migrated with new names (making zero-downtime
  deployment on multiple servers easier to manage).

  #### Capacity planning

  Each consumer sets its own `prefetch_count` property on its channel.

  This way, a single consumer can define how many messages can be handled at
  any given time.

  Handling is parallelized via the usage of tasks: assuming a `prefetch_count`
  value of 5, a maximum of 5 tasks at any given time are spawned to handle
  incoming messages.

  Tasks are supervised, by default under a `Task.Supervisor` process named
  `Rbt.Consumer.DefaultTaskSupervisor`. It's possible to use a different one
  simply by passing `task_supervisor: <name-of-the-new-supervisor>` to the
  starting configuration of the consumer. Note that the new `Task.Supervisor`
  needs to be started (see the relevant `Task.Supervisor` docs for details).

  #### Retry and Failure

  Assuming the consumer manages its own topology, it's possible to control:

  - retry behaviour: how many times should the consumer attempt to process this
    message?
  - forward failures: after deciding that it's not possible to handle the
    message or reaching the maximum amount of allowed retries, what should the
    consumer do with the message?

  In case `forward_failures` is set to `true`, the queue associated with the consumer
  is setup with a dead-letter-exchange flag. In case of permanent failure, the
  message gets rejected, triggering the dead-lettering rule. It will be forwarded to
  the "failures" exchange.

  This opens the possibility of creating an infrastructure of queues and consumers that
  would process failures published on "failures" exchanges.
  """

  @behaviour :gen_statem

  alias Rbt.{Channel, Backoff, Consumer.Deliver}
  import Rbt.Registry.Consumer, only: [via: 2]

  @default_definitions %{
    exchange_name: nil,
    queue_name: nil,
    routing_keys: []
  }

  @default_config %{
    max_workers: 5,
    durable_objects: false,
    max_retries: :infinity,
    forward_failures: false,
    create_infrastructure: false,
    task_supervisor: Rbt.Consumer.DefaultTaskSupervisor,
    instrumentation: Rbt.Instrumentation.NoOp.Consumer
  }

  @config_keys Map.keys(@default_config)

  defstruct conn_ref: nil,
            channel: nil,
            definitions: @default_definitions,
            config: @default_config,
            consumer_tag: nil,
            handler: nil,
            backoff_intervals: Backoff.default_intervals()

  @type exchange_name :: String.t()
  @type queue_name :: String.t()

  @type config :: %{
          max_workers: pos_integer(),
          durable_objects: boolean(),
          max_retries: pos_integer() | :infinity,
          forward_failures: boolean(),
          create_infrastructure: boolean(),
          task_supervisor: module(),
          instrumentation: module()
        }

  @type definitions :: %{
          exchange_name: nil | exchange_name(),
          queue_name: nil | queue_name(),
          routing_keys: [String.t()]
        }

  @type t :: %__MODULE__{
          conn_ref: nil | Rbt.Conn.name(),
          channel: nil | AMQP.Channel.t(),
          definitions: definitions(),
          config: config(),
          consumer_tag: nil | String.t(),
          handler: nil | module(),
          backoff_intervals: Backoff.intervals()
        }

  ################################################################################
  ################################## PUBLIC API ##################################
  ################################################################################

  @doc """
  Start a consumer given a connection name and a handler module. Defaults to the
  configuration provided by the handler module.
  """
  @spec start_link(Rbt.Conn.name(), module()) :: {:ok, pid()} | {:error, term()}
  def start_link(conn_ref, handler), do: start_link(conn_ref, handler, handler.config())

  @doc """
  Start a consumer given a connection name, a handler module and an explicit
  configuration map.
  """
  @spec start_link(Rbt.Conn.name(), module(), config()) :: {:ok, pid()} | {:error, term()}
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

  @doc """
  Cancels consumption for a consumer (defined by exchange name and queue name).
  """
  @spec cancel(exchange_name(), queue_name()) ::
          :ok | {:ok, :requested} | {:error, :in_progress} | {:error, :invalid}
  def cancel(exchange_name, queue_name) do
    :gen_statem.call(via(exchange_name, queue_name), :cancel)
  end

  @doc """
  Starts/resume consumption for a consumer (defined by exchange name and queue name).
  """
  @spec consume(exchange_name(), queue_name()) ::
          :ok | {:ok, :requested} | {:error, :in_progress} | {:error, :invalid}
  def consume(exchange_name, queue_name) do
    :gen_statem.call(via(exchange_name, queue_name), :consume)
  end

  @doc """
  Changes capacity for a consumer (defined by exchange name and queue name).
  This will both update the `prefetch_count` on the consumer channel.
  """
  @spec scale(exchange_name(), queue_name(), pos_integer()) :: :ok | {:error, :invalid}
  def scale(exchange_name, queue_name, max_workers) do
    :gen_statem.call(via(exchange_name, queue_name), {:scale, max_workers})
  end

  @doc """
  Returns the status for a consumer (defined by exchange name and queue name).
  """
  @spec status(exchange_name(), queue_name()) :: %{state: atom(), data: t()}
  def status(exchange_name, queue_name) do
    :gen_statem.call(via(exchange_name, queue_name), :status)
  end

  @doc """
  Returns the status for a consumer (defined by its pid).
  """
  @spec status(GenServer.name()) :: %{state: atom(), data: t()}
  def status(consumer_ref) do
    :gen_statem.call(consumer_ref, :status)
  end

  @doc """
  Returns the topology information for a consumer (defined by its pid).
  """
  @spec topology_info(GenServer.name()) :: %{
          state: atom(),
          conn_ref: Rbt.Conn.name(),
          infrastructure: definitions(),
          config: %{
            forward_failures: boolean(),
            max_retries: pos_integer() | :infinity,
            max_workers: pos_integer()
          }
        }
  def topology_info(consumer_ref) do
    status = status(consumer_ref)
    config = Map.take(status.data.config, [:forward_failures, :max_retries, :max_workers])

    %{
      state: status.state,
      conn_ref: status.data.conn_ref,
      infrastructure: status.data.definitions,
      config: config
    }
  end

  ################################################################################
  ################################## CALLBACKS ###################################
  ################################################################################

  @doc """
  Returns a child specification suitable for inserting a consumer
  inside a supervision tree.
  """
  def child_spec(opts) do
    conn_ref = Keyword.fetch!(opts, :conn_ref)
    handler = Keyword.fetch!(opts, :handler)
    config = Enum.into(opts, @default_config)

    %{
      id: {__MODULE__, opts},
      start: {__MODULE__, :start_link, [conn_ref, handler, config]},
      type: :worker,
      restart: :permanent,
      shutdown: 500
    }
  end

  @doc false
  def callback_mode, do: :handle_event_function

  @doc false
  def init({conn_ref, handler, opts}) do
    definitions = Map.fetch!(opts, :definitions)
    config = Map.take(opts, @config_keys)

    data = %__MODULE__{
      conn_ref: conn_ref,
      definitions: definitions,
      config: Map.merge(@default_config, config),
      handler: handler
    }

    instrument_setup!(data)

    Process.flag(:trap_exit, true)

    action = {:next_event, :internal, :try_declare}
    {:ok, :idle, data, action}
  end

  ################################################################################
  ############################### STATE CALLBACKS ################################
  ################################################################################

  # SETUP OBJECTS AND AUTO SUBSCRIPTION

  @doc false
  def handle_event(event_type, :try_declare, :idle, data)
      when event_type in [:internal, :state_timeout] do
    case Channel.open(data.conn_ref) do
      {:ok, channel} ->
        set_prefetch_count!(channel, data.config)
        Process.monitor(channel.pid)

        if data.config.create_infrastructure do
          setup_infrastructure!(channel, data.definitions, data.config)
        end

        action = {:next_event, :internal, :subscribe}

        new_data =
          data
          |> Backoff.reset!()
          |> Map.put(:channel, channel)

        {:next_state, :unsubscribed, new_data, action}

      _error ->
        {:ok, delay, new_data} = Backoff.next_interval(data)
        action = {:state_timeout, delay, :try_declare}
        {:keep_state, %{new_data | channel: nil}, action}
    end
  end

  def handle_event(:internal, :subscribe, :unsubscribed, data) do
    subscribe!(data.channel, data.definitions.queue_name)

    {:next_state, :subscribing, data}
  end

  # MESSAGE HANDLING

  def handle_event(:info, {:basic_deliver, payload, meta}, :subscribed, data) do
    Task.Supervisor.async_nolink(data.config.task_supervisor, fn ->
      handle_delivery!(payload, meta, data)
    end)

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

  # SCALE

  def handle_event({:call, from}, {:scale, max_workers}, state, data)
      when state in [:unsubscribed, :subscribed] do
    new_data = put_in(data.config.max_workers, max_workers)
    set_prefetch_count!(data.channel, new_data.config)
    action = {:reply, from, :ok}
    {:keep_state, new_data, action}
  end

  def handle_event({:call, from}, {:scale, _max_workers}, _other_state, _data) do
    action = {:reply, from, {:error, :invalid}}
    {:keep_state_and_data, action}
  end

  # STATUS

  def handle_event({:call, from}, :status, state, data) do
    reply = %{state: state, data: data}
    action = {:reply, from, reply}
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

  def handle_event(:info, {task_ref, result}, state, data)
      when is_reference(task_ref) and state not in [:idle] do
    case result do
      {:skip, meta} ->
        ack!(data.channel, meta.delivery_tag)

      {:ok, meta} ->
        ack!(data.channel, meta.delivery_tag)

      {:error, :no_retry, meta} ->
        reject!(data.channel, meta.delivery_tag)

      {:error, :retry, _payload, meta, :infinity} ->
        reject_and_requeue!(data.channel, meta.delivery_tag)

      {:error, :retry, payload, meta, retry_count} ->
        requeue_with_retry!(payload, meta, data, retry_count)
    end

    :keep_state_and_data
  end

  def handle_event(:info, {:DOWN, _ref, :process, _pid, :normal}, _state, _data) do
    :keep_state_and_data
  end

  def handle_event(:info, {:DOWN, _ref, :process, _pid, reason}, _state, _data) do
    {:stop, reason}
  end

  @doc false
  def terminate(_reason, _state, data) do
    instrument_teardown!(data)

    if data.channel do
      AMQP.Channel.close(data.channel)
    end
  end

  ################################################################################
  ################################### PRIVATE ####################################
  ################################################################################

  defp retry_exchange_name(exchange_name), do: exchange_name <> "-retries"

  defp failure_exchange_name(exchange_name), do: exchange_name <> "-failures"

  # AMQP operations

  defp set_prefetch_count!(channel, config) do
    max_workers = Map.fetch!(config, :max_workers)
    :ok = AMQP.Basic.qos(channel, prefetch_count: max_workers)
  end

  defp setup_infrastructure!(channel, definitions, config) do
    setup_primary_objects!(channel, definitions, config)
    setup_retry_objects!(channel, definitions, config)
    setup_forward_failure_objects!(channel, definitions, config)
  end

  defp setup_primary_objects!(channel, definitions, config) do
    declare_exchange!(channel, definitions.exchange_name, config)
    declare_queue!(channel, definitions.exchange_name, definitions.queue_name, config)

    bind_queue!(
      channel,
      definitions.queue_name,
      definitions.exchange_name,
      definitions.routing_keys
    )
  end

  defp setup_retry_objects!(channel, definitions, config) do
    declare_exchange!(channel, retry_exchange_name(definitions.exchange_name), config)

    bind_queue!(channel, definitions.queue_name, retry_exchange_name(definitions.exchange_name), [
      definitions.queue_name
    ])
  end

  defp setup_forward_failure_objects!(channel, definitions, config) do
    if Map.fetch!(config, :forward_failures) do
      declare_exchange!(channel, failure_exchange_name(definitions.exchange_name), config)
    else
      :ok
    end
  end

  defp declare_exchange!(channel, exchange_name, config) do
    durable = Map.fetch!(config, :durable_objects)

    :ok = AMQP.Exchange.declare(channel, exchange_name, :topic, durable: durable)
  end

  defp declare_queue!(channel, exchange_name, queue_name, config) do
    durable = Map.fetch!(config, :durable_objects)
    forward_failures = Map.fetch!(config, :forward_failures)

    queue_opts =
      if forward_failures do
        [
          durable: durable,
          arguments: [{"x-dead-letter-exchange", :longstr, failure_exchange_name(exchange_name)}]
        ]
      else
        [durable: durable]
      end

    {:ok, _queue_stats} = AMQP.Queue.declare(channel, queue_name, queue_opts)
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
      {:infinity, _retry_count} ->
        handle_with_infinite_retries(payload, meta, data)

      {max_retries, retry_count} when retry_count >= max_retries ->
        {:error, :no_retry, meta}

      {_max_retries, retry_count} ->
        handle_with_limited_retries(payload, meta, data, retry_count)
    end
  end

  defp get_retry_count(meta) do
    {"retry_count", _, retry_count} =
      List.keyfind(meta.headers, "retry_count", 0, {"retry_count", :long, 0})

    retry_count
  end

  defp handle_with_infinite_retries(payload, meta, data) do
    case Deliver.handle(payload, meta, data) do
      {:skip, event} ->
        instrument_event_skip!(event, meta, data)
        {:skip, meta}

      {:ok, event, duration} ->
        instrument_event_ok!(event, meta, data, duration)
        {:ok, meta}

      {:error, _retry_policy, reason, event} ->
        instrument_event_retry!(event, reason, meta, data)
        {:error, :retry, payload, meta, :infinity}
    end
  end

  defp handle_with_limited_retries(payload, meta, data, retry_count) do
    case Deliver.handle(payload, meta, data) do
      {:skip, event} ->
        instrument_event_skip!(event, meta, data)
        {:skip, meta}

      {:ok, event, duration} ->
        instrument_event_ok!(event, meta, data, duration)
        {:ok, meta}

      {:error, :retry, reason, event} ->
        instrument_event_error!(event, reason, meta, data)
        {:error, :retry, payload, meta, retry_count + 1}

      {:error, :no_retry, reason, event} ->
        instrument_event_retry!(event, reason, meta, data)
        {:error, :no_retry, meta}
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

  defp instrument_setup!(data) do
    %{exchange_name: exchange_name, queue_name: queue_name} = data.definitions
    data.config.instrumentation.setup(exchange_name, queue_name)
  end

  defp instrument_teardown!(data) do
    %{exchange_name: exchange_name, queue_name: queue_name} = data.definitions
    data.config.instrumentation.teardown(exchange_name, queue_name)
  end

  defp instrument_consume_ok!(data) do
    %{exchange_name: exchange_name, queue_name: queue_name} = data.definitions
    data.config.instrumentation.on_consume(exchange_name, queue_name)
  end

  defp instrument_cancel_ok!(data) do
    %{exchange_name: exchange_name, queue_name: queue_name} = data.definitions
    data.config.instrumentation.on_cancel(exchange_name, queue_name)
  end

  defp instrument_event_skip!(event, meta, data) do
    %{exchange_name: exchange_name, queue_name: queue_name} = data.definitions
    data.config.instrumentation.on_event_skip(exchange_name, queue_name, event, meta)
  end

  defp instrument_event_ok!(event, meta, data, duration) do
    %{exchange_name: exchange_name, queue_name: queue_name} = data.definitions
    data.config.instrumentation.on_event_ok(exchange_name, queue_name, event, meta, duration)
  end

  defp instrument_event_error!(event, error, meta, data) do
    %{exchange_name: exchange_name, queue_name: queue_name} = data.definitions
    data.config.instrumentation.on_event_error(exchange_name, queue_name, event, meta, error)
  end

  defp instrument_event_retry!(event, error, meta, data) do
    %{exchange_name: exchange_name, queue_name: queue_name} = data.definitions
    data.config.instrumentation.on_event_retry(exchange_name, queue_name, event, meta, error)
  end
end
