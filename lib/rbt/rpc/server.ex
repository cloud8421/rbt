defmodule Rbt.Rpc.Server do
  @moduledoc """
  This module implements a RabbitMQ powered rpc server according to the topology
  expressed at: <https://www.rabbitmq.com/tutorials/tutorial-six-elixir.html>.

                  ┌──────────────────────┐
                  │Request               │   ┌────────────┐
              ┌──▶│reply_to: amqp.gen-123│──▶│rpc -> chat │──┐
              │   │correlation_id: abc   │   └────────────┘  │
              │   └──────────────────────┘                   │
              │                                              │
              │                                              ▼
      ┌──────────────┐                               ┌──────────────┐
      │    Client    │                               │    Server    │
      └──────────────┘                               └──────────────┘
              ▲                                              │
              │                                              │
              │   ┌──────────────────────┐                   │
              │   │Response              │   ┌────────────┐  │
              └───│correlation_id: abc   │◀──│amqp.gen-123│◀─┘
                  │                      │   └────────────┘
                  └──────────────────────┘

  #### Usage

  Mount the `Rbt.Rpc.Server` in the target application:

      children = [
        Rbt.Rpc.Server.child_spec(
          conn_ref: :rpc_server_conn,
          namespace: "rbt-rpc-server-test",
          config: %{max_workers: 20}
        )
      ]

  #### Implementation details

  When starting, the rpc server process declares a namespace (e.g. `auth`) that identifies
  the generic domain of things the server is capable of doing.

  As a consequence, a queue is created with the same namespace (prefixed with `rpc -> ` for clarity).

  The server then starts consuming the queue.

  The server is able to consume messages with the following properties:

  - A `reply_to` header, which is needed to route the reply to the queue that is consumed by the rpc caller
  - A `correlation_id` header, which will be sent together with the reply to allow the caller to process multiple rpcs concurrently
  - A body encoded as via `:erlang.term_to_binary/2`, representing a function call. More details in the "Payload" section.

  #### Payload

  The expected payload is a function specification. Three forms are allowed:

  - An anonymous function: `fn() -> 1 + 1 end`
  - A named function with arity 0: `Nodes.list/0`
  - A mfa tuple: `{String, :upcase, ["abc"]}`
  """

  @behaviour :gen_statem

  alias Rbt.{Channel, Backoff, Data}

  @default_exchange ""

  @default_queue_opts []
  @default_max_workers 5

  defstruct conn_ref: nil,
            mon_ref: nil,
            namespace: nil,
            queue_opts: @default_queue_opts,
            max_workers: @default_max_workers,
            channel: nil,
            consumer_tag: nil,
            backoff_intervals: Backoff.default_intervals(),
            task_supervisor: Rbt.Rpc.DefaultTaskSupervisor,
            instrumentation: Rbt.Instrumentation.NoOp.Rpc.Server

  def start_link(conn_ref, namespace, config) do
    :gen_statem.start_link(__MODULE__, {conn_ref, namespace, config}, [])
  end

  ################################################################################
  ################################## CALLBACKS ###################################
  ################################################################################

  def child_spec(opts) do
    conn_ref = Keyword.fetch!(opts, :conn_ref)
    namespace = Keyword.fetch!(opts, :namespace)
    config = Keyword.get(opts, :config, %{})

    %{
      id: {__MODULE__, Rbt.UUID.generate()},
      start: {__MODULE__, :start_link, [conn_ref, namespace, config]},
      type: :worker,
      restart: :permanent,
      shutdown: 500
    }
  end

  def callback_mode, do: :handle_event_function

  def init({conn_ref, namespace, config}) do
    data = %__MODULE__{
      conn_ref: conn_ref,
      namespace: namespace,
      queue_opts: Map.get(config, :queue_opts, @default_queue_opts),
      max_workers: Map.get(config, :max_workers, @default_max_workers)
    }

    Process.flag(:trap_exit, true)

    instrument_setup!(namespace, data)

    action = {:next_event, :internal, :try_declare}
    {:ok, :idle, data, action}
  end

  ################################################################################
  ############################### STATE CALLBACKS ################################
  ################################################################################

  # SETUP OBJECTS

  def handle_event(event_type, :try_declare, :idle, data)
      when event_type in [:internal, :state_timeout] do
    case Channel.open(data.conn_ref) do
      {:ok, channel} ->
        mon_ref = Process.monitor(channel.pid)

        set_prefetch_count!(channel, data)

        setup_infrastructure!(channel, data)

        new_data =
          data
          |> Backoff.reset!()
          |> Map.put(:mon_ref, mon_ref)
          |> Map.put(:channel, channel)

        # instrument_on_connect!(new_data)
        {:keep_state, new_data}

      _error ->
        {:ok, delay, new_data} = Backoff.next_interval(data)

        # instrument_on_disconnect!(new_data)

        action = {:state_timeout, delay, :try_declare}
        {:keep_state, %{new_data | channel: nil, mon_ref: nil}, action}
    end
  end

  # SERVER SENT CONFIRMATIONS

  def handle_event(:info, {:basic_consume_ok, %{consumer_tag: consumer_tag}}, :idle, data) do
    # instrument_consume_ok!(data)
    {:next_state, :ready, %{data | consumer_tag: consumer_tag}}
  end

  # RECONNECTION

  def handle_event(:info, {:DOWN, ref, :process, pid, _reason}, _state, data) do
    if data.mon_ref == ref and data.channel.pid == pid do
      # instrument_on_disconnect!(data)
      action = {:next_event, :internal, :try_declare}

      new_data =
        data
        |> Map.put(:channel, nil)
        |> Map.put(:mon_ref, nil)
        |> Map.put(:consumer_tag, nil)

      {:next_state, :idle, new_data, action}
    else
      :keep_state_and_data
    end
  end

  # MESSAGE HANDLING

  def handle_event(:info, {:basic_deliver, payload, meta}, :ready, data) do
    Task.Supervisor.async_nolink(data.task_supervisor, fn ->
      payload
      |> process!
      |> Tuple.append(meta)
    end)

    :keep_state_and_data
  end

  def handle_event(:info, {:basic_deliver, _payload, meta}, _other_state, data) do
    AMQP.Basic.reject(data.channel, meta.delivery_tag, requeue: false)
    :keep_state_and_data
  end

  def handle_event(:info, {_task_ref, result}, :ready, data) do
    case result do
      {:ok, {elapsed_us, value}, meta} ->
        options = [
          correlation_id: meta.correlation_id,
          mandatory: true
        ]

        AMQP.Basic.publish(
          data.channel,
          @default_exchange,
          meta.reply_to,
          Data.encode!({:ok, value}, "application/octet-stream"),
          options
        )

        instrument_process!(elapsed_us, data)

        ack!(data.channel, meta.delivery_tag)

      {:error, reason, meta} ->
        options = [
          correlation_id: meta.correlation_id,
          mandatory: true
        ]

        AMQP.Basic.publish(
          data.channel,
          @default_exchange,
          meta.reply_to,
          Data.encode!({:error, reason}, "application/octet-stream"),
          options
        )

        instrument_error!(reason, data)

        ack!(data.channel, meta.delivery_tag)
    end

    :keep_state_and_data
  end

  def terminate(_reason, _state, data) do
    instrument_teardown!(data.namespace, data)
  end

  ################################################################################
  ################################### PRIVATE ####################################
  ################################################################################

  defp set_prefetch_count!(channel, config) do
    :ok = AMQP.Basic.qos(channel, prefetch_count: config.max_workers)
  end

  defp setup_infrastructure!(channel, config) do
    {:ok, _} = AMQP.Queue.declare(channel, config.namespace, config.queue_opts)

    {:ok, _consumer_tag} = AMQP.Basic.consume(channel, config.namespace, nil)
  end

  defp ack!(channel, delivery_tag) do
    AMQP.Basic.ack(channel, delivery_tag)
  end

  defp process!(payload) do
    case Data.decode!(payload, "application/octet-stream") do
      {m, f, a} ->
        do_process(m, f, a)

      other ->
        {:error, {:invalid_spec, other}}
    end
  end

  defp do_process(m, f, a) do
    try do
      {:ok, :timer.tc(m, f, a)}
    rescue
      error ->
        {:error, error}
    catch
      error ->
        {:error, error}

      _exit, reason ->
        {:error, reason}
    end
  end

  ################################################################################
  ############################### INSTRUMENTATION ################################
  ################################################################################

  defp instrument_setup!(namespace, data) do
    data.instrumentation.setup(namespace)
  end

  defp instrument_teardown!(namespace, data) do
    data.instrumentation.teardown(namespace)
  end

  defp instrument_process!(duration, data) do
    data.instrumentation.on_process(data.namespace, duration)
  end

  defp instrument_error!(reason, data) do
    data.instrumentation.on_error(data.namespace, reason)
  end
end
