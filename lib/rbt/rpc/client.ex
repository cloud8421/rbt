defmodule Rbt.Rpc.Client do
  @moduledoc """
  This module implements a RabbitMQ powered rpc client according to the topology
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

  Mount the `Rbt.Rpc.Client` in the target application, giving it a name:

      children = [
        Rbt.Rpc.Client.child_spec(conn_ref: :rpc_client_conn, name: RpcClient)
      ]

  After that, you can call:

      Rbt.Rpc.Client.call(Assistant.Rabbit.Rpc.Client, "chat", {String, :upcase, ["a"]})

  #### Implementation details

  When starting the rpc client declares an exclusive queue that will be auto-deleted in case the client itself crashes.

  It then starts consuming the queue.

  The process of making an rpc call has these conceptual steps:

  - The client generates a unique uuid, added as a header to the message as `correlation_id`
  - The client sets the `reply_to` header for message as the queue it creates on start
  - It encodes the function spec as a binary via `:erlang.term_to_binary/2` (for details about supported payloads, see the "Payload"
    section in the `Rabbit.Rpc.Server` documentation.
  - The client stores in its own state pairs of publishing tags and references to the process who called the rpc. This is needed
    to make sure that if multiple processes ask the client process to perform rpc calls, the client can correctly route the response
    back to each process.

  #### RPC return values

  An rpc call can return:

  - `{:rpc_ok, result}`
  - `{:rpc_error, error}`

  It also fails automatically after 1.5 seconds, crashing the caller.
  """

  @behaviour :gen_statem
  @default_exchange ""
  @call_content_type "application/octet-stream"
  @call_timeout 1500

  alias Rbt.{Channel, Backoff, Data}

  defstruct conn_ref: nil,
            mon_ref: nil,
            queue_name: nil,
            continuations: %{},
            consumer_tag: nil,
            backoff_intervals: Backoff.default_intervals(),
            instrumentation: Rbt.Instrumentation.NoOp.Rpc.Client

  def start_link(conn_ref, name) do
    :gen_statem.start_link({:local, name}, __MODULE__, conn_ref, [])
  end

  def call(name, namespace, fun, timeout \\ @call_timeout) do
    :gen_statem.call(name, {:rpc_call, namespace, fun}, timeout)
  end

  def status(server_ref) do
    :gen_statem.call(server_ref, :status)
  end

  def topology_info(server_ref) do
    {state, data} = status(server_ref)

    %{
      state: state,
      queue_name: data.queue_name,
      pending: Map.size(data.continuations),
      conn_ref: data.conn_ref
    }
  end

  ################################################################################
  ################################## CALLBACKS ###################################
  ################################################################################

  def child_spec(opts) do
    conn_ref = Keyword.fetch!(opts, :conn_ref)
    name = Keyword.fetch!(opts, :name)

    %{
      id: {__MODULE__, name},
      start: {__MODULE__, :start_link, [conn_ref, name]},
      type: :worker,
      restart: :permanent,
      shutdown: 500
    }
  end

  def callback_mode, do: :state_functions

  def init(conn_ref) do
    data = %__MODULE__{
      conn_ref: conn_ref
    }

    action = {:next_event, :internal, :try_declare}
    {:ok, :idle, data, action}
  end

  def idle(event_type, :try_declare, data)
      when event_type in [:internal, :state_timeout] do
    case Channel.open(data.conn_ref) do
      {:ok, channel} ->
        mon_ref = Process.monitor(channel.pid)

        queue_name = setup_infrastructure!(channel)

        new_data =
          data
          |> Backoff.reset!()
          |> Map.put(:mon_ref, mon_ref)
          |> Map.put(:channel, channel)
          |> Map.put(:queue_name, queue_name)

        action = {:next_event, :internal, :subscribe}

        {:next_state, :unsubscribed, new_data, action}

      _error ->
        {:ok, delay, new_data} = Backoff.next_interval(data)

        action = {:state_timeout, delay, :try_declare}

        {:keep_state,
         %{new_data | channel: nil, mon_ref: nil, queue_name: nil, consumer_tag: nil}, action}
    end
  end

  def idle({:call, from}, :status, data) do
    {:keep_state_and_data, {:reply, from, {:idle, data}}}
  end

  def unsubscribed(:internal, :subscribe, data) do
    subscribe!(data.channel, data.queue_name)

    {:next_state, :subscribing, data}
  end

  def unsubscribed({:call, from}, {:rpc_call, _namespace, _fun_}, _data) do
    reply = {:reply, from, {:error, :not_subscribed}}
    {:keep_state_and_data, reply}
  end

  def unsubscribed({:call, from}, :status, data) do
    {:keep_state_and_data, {:reply, from, {:unsubscribed, data}}}
  end

  def subscribing(:info, {:basic_consume_ok, %{consumer_tag: consumer_tag}}, data) do
    {:next_state, :subscribed, %{data | consumer_tag: consumer_tag}}
  end

  def subscribing({:call, from}, {:rpc_call, _namespace, _fun_}, _data) do
    reply = {:reply, from, {:error, :not_subscribed}}
    {:keep_state_and_data, reply}
  end

  def subscribing({:call, from}, :status, data) do
    {:keep_state_and_data, {:reply, from, {:subscribing, data}}}
  end

  def subscribed({:call, from}, {:rpc_call, namespace, fun}, data) do
    correlation_id = publish_rpc_call!(namespace, fun, data)

    {:keep_state, add_continuation(data, namespace, correlation_id, from)}
  end

  def subscribed({:call, from}, :status, data) do
    {:keep_state_and_data, {:reply, from, {:subscribed, data}}}
  end

  def subscribed(:info, {:basic_deliver, payload, meta}, data) do
    case remove_continuation(data, meta.correlation_id) do
      {:not_present, ^data} ->
        :keep_state_and_data

      {{from, namespace, start_epoch}, new_data} ->
        instrument_end!(namespace, meta.correlation_id, start_epoch, data)
        {:keep_state, new_data, handle_reply(from, payload)}
    end
  end

  ################################################################################
  ################################### PRIVATE ####################################
  ################################################################################

  # AMQP operations

  defp setup_infrastructure!(channel) do
    queue_opts = [exclusive: true, auto_delete: true]
    {:ok, %{queue: queue}} = AMQP.Queue.declare(channel, "", queue_opts)
    queue
  end

  defp subscribe!(channel, queue_name) do
    {:ok, _consumer_tag} = AMQP.Basic.consume(channel, queue_name, nil)
  end

  defp publish_rpc_call!(namespace, fun, data) do
    payload = Data.encode!(fun, @call_content_type)
    correlation_id = Rbt.UUID.generate()

    options = [
      correlation_id: correlation_id,
      content_type: @call_content_type,
      mandatory: true,
      reply_to: data.queue_name
    ]

    AMQP.Basic.publish(data.channel, @default_exchange, namespace, payload, options)

    instrument_start!(namespace, correlation_id, data)

    correlation_id
  end

  # State management

  defp add_continuation(data, namespace, correlation_id, from) do
    continuation = {from, namespace, unix_now()}
    %{data | continuations: Map.put(data.continuations, correlation_id, continuation)}
  end

  defp remove_continuation(data, correlation_id) do
    {continuation, rest} = Map.pop(data.continuations, correlation_id, :not_present)

    {continuation, %{data | continuations: rest}}
  end

  defp unix_now do
    DateTime.utc_now()
    |> DateTime.to_unix(:microsecond)
  end

  # Replies

  defp handle_reply(from, payload) do
    case Data.decode!(payload, @call_content_type) do
      {:ok, result} ->
        {:reply, from, {:rpc_ok, result}}

      {:error, reason} ->
        if Exception.exception?(reason) do
          {:reply, from, {:rpc_error, Exception.message(reason)}}
        else
          {:reply, from, {:rpc_error, reason}}
        end
    end
  end

  ################################################################################
  ############################### INSTRUMENTATION ################################
  ################################################################################

  defp instrument_start!(namespace, correlation_id, data) do
    data.instrumentation.on_rpc_start(namespace, correlation_id)
  end

  defp instrument_end!(correlation_id, namespace, start_epoch, data) do
    duration = unix_now() - start_epoch
    data.instrumentation.on_rpc_end(namespace, correlation_id, duration)
  end
end
