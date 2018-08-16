defmodule Rbt.Instrumentation.NoOp do
  defmodule Consumer do
    @behaviour Rbt.Instrumentation.Consumer

    def setup(_exchange_name, _queue_name), do: :ok
    def teardown(_exchange_name, _queue_name), do: :ok
    def on_consume(_exchange_name, _queue_name), do: :ok
    def on_cancel(_exchange_name, _queue_name), do: :ok
    def on_event_skip(_exchange_name, _queue_name, _event, _meta), do: :ok
    def on_event_ok(_exchange_name, _queue_name, _event, _meta, _duration), do: :ok
    def on_event_error(_exchange_name, _queue_name, _event, _meta, _error), do: :ok
  end

  defmodule Producer do
    @behaviour Rbt.Instrumentation.Producer

    def setup(_exchange_name), do: :ok
    def teardown(_exchange_name), do: :ok
    def on_connect(_exchange_name), do: :ok
    def on_disconnect(_exchange_name), do: :ok
    def on_publish_ok(_exchange_name, _event, _buffer_size), do: :ok
    def on_publish_error(_exchange_name, _event, _error, _buffer_size), do: :ok
    def on_queue(_exchange_name, _event, _buffer_size), do: :ok
  end
end
