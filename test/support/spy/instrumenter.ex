defmodule Rbt.Spy.Instrumenter do
  defmodule Consumer do
    @behaviour Rbt.Instrumentation.Consumer
    use GenServer

    def start_link(test_process) do
      GenServer.start_link(__MODULE__, test_process, name: __MODULE__)
    end

    def init(test_process) do
      {:ok, test_process}
    end

    def setup(exchange_name, queue_name) do
      GenServer.call(__MODULE__, {:setup, {exchange_name, queue_name}})
    end

    def teardown(exchange_name, queue_name) do
      GenServer.call(__MODULE__, {:teardown, {exchange_name, queue_name}})
    end

    def on_consume(exchange_name, queue_name) do
      GenServer.call(__MODULE__, {:on_consume, {exchange_name, queue_name}})
    end

    def on_cancel(exchange_name, queue_name) do
      GenServer.call(__MODULE__, {:on_cancel, {exchange_name, queue_name}})
    end

    def on_event_skip(exchange_name, queue_name, event, meta) do
      GenServer.call(__MODULE__, {:on_event_skip, {exchange_name, queue_name, event, meta}})
    end

    def on_event_ok(exchange_name, queue_name, event, meta, duration) do
      GenServer.call(
        __MODULE__,
        {:on_event_ok, {exchange_name, queue_name, event, meta, duration}}
      )
    end

    def on_event_error(exchange_name, queue_name, event, meta, error) do
      GenServer.call(
        __MODULE__,
        {:on_event_error, {exchange_name, queue_name, event, meta, error}}
      )
    end

    def on_event_retry(exchange_name, queue_name, event, meta, error) do
      GenServer.call(
        __MODULE__,
        {:on_event_retry, {exchange_name, queue_name, event, meta, error}}
      )
    end

    def handle_call({event_name, params}, _from, test_process) do
      send(test_process, {event_name, params})
      {:reply, :ok, test_process}
    end
  end

  defmodule Producer do
    @behaviour Rbt.Instrumentation.Producer
    use GenServer

    def start_link(test_process) do
      GenServer.start_link(__MODULE__, test_process, name: __MODULE__)
    end

    def init(test_process) do
      {:ok, test_process}
    end

    def setup(exchange_name) do
      GenServer.call(__MODULE__, {:setup, exchange_name})
    end

    def teardown(exchange_name) do
      GenServer.call(__MODULE__, {:teardown, exchange_name})
    end

    def on_connect(exchange_name) do
      GenServer.call(__MODULE__, {:on_connect, exchange_name})
    end

    def on_disconnect(exchange_name) do
      GenServer.call(__MODULE__, {:on_disconnect, exchange_name})
    end

    def on_publish_ok(exchange_name, event, buffer_size) do
      GenServer.call(__MODULE__, {:on_publish_ok, {exchange_name, event, buffer_size}})
    end

    def on_publish_error(exchange_name, event, error, buffer_size) do
      GenServer.call(__MODULE__, {:on_publish_error, {exchange_name, event, error, buffer_size}})
    end

    def on_queue(exchange_name, event, buffer_size) do
      GenServer.call(__MODULE__, {:on_queue, {exchange_name, event, buffer_size}})
    end

    def handle_call({event_name, params}, _from, test_process) do
      send(test_process, {event_name, params})
      {:reply, :ok, test_process}
    end
  end
end
