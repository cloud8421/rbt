# Rbt

Work in progress, not usable yet.

## Guidelines

- Self-configuring topology
- Small, explicit and composable building blocks
- Configuration only for compile-time variables (e.g. which JSON decoder to use)
- Always pass down configuration from the top, e.g. application -> supervisor -> single worker
- Always pass options explicitly at start
- Instrumentable
- Smallest possible dependency surface (make as many as possible optional)
- Support multiple mimetypes
- Don't hide APIs, rather provide ways to compose them
- Introspection to see running components at any given time

## Features

- [x] Topic consumers
  - [x] auto retries with backoff
  - [x] forward failures to separate exchange for capture
  - [x] parallelized, bounded message handling
  - [x] instrumentation hooks
  - [x] manual consume/cancel control
  - [x] multiple content types (erlang, json)
- [x] Topic publishers
  - [x] internal buffering in case of disconnection
  - [x] auto-fingerprint of published messages with generated uuid
  - [x] instrumentation hooks
  - [x] multiple content types (erlang, json)
  - [x] test helpers
- [x] RPC server
- [x] RPC client
- [ ] Complete docs

## Usage

RBT components can be composed via supervision trees. Here's a fairly extended example that starts two connections (one for consumers, one for producers), a producer and a consumer.

```elixir
defmodule ExampleSupervisor do
  use Supervisor

  def start_link(vhost_url) do
    Supervisor.start_link(__MODULE__, vhost_url)
  end

  def init(opts) do
    vhost_url = Keyword.fetch!(opts, :vhost_url)

    children = [
      {Rbt.Conn, uri: vhost_url, name: :prod_conn},
      {Rbt.Conn, uri: vhost_url, name: :cons_conn},
      {Rbt.Producer, conn_ref: :prod_conn, definitions: %{exchange_name: "test-exchange"}},
      {Rbt.Consumer.Topic,
       conn_ref: :cons_conn,
       handler: MyHandler,
       definitions: %{
         exchange_name: "test-exchange",
         queue_name: "test-queue",
         routing_keys: ["test.topic"]
       },
       max_retries: 3}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
```

The supervisor itself can be mounted inside the main application tree by adding `{ExampleSupervisor, vhost_url: "amqp://"}`.

The consumer worker references a `MyHandler` module which needs to implement the `Rbt.Consumer.Handler` behaviour:

```elixir
defmodule MyHandler do
  use Rbt.Consumer.Handler

  def handle_event(event, meta) do
    IO.inspect(event)
    IO.inspect(meta)
    :ok
  end
end
```

To publish a message, it's possible to call:

```elixir
Rbt.Producer.publish("test-exchange", "test.topic", %{some: "data"}, message_id: "my-client-id")
```
