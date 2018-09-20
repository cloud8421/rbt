defmodule Rbt.Instrumentation.NoOp do
  @moduledoc false

  defmodule Consumer do
    @moduledoc false
    @behaviour Rbt.Instrumentation.Consumer

    def setup(_exchange_name, _queue_name), do: :ok
    def teardown(_exchange_name, _queue_name), do: :ok
    def on_consume(_exchange_name, _queue_name), do: :ok
    def on_cancel(_exchange_name, _queue_name), do: :ok
    def on_event_skip(_exchange_name, _queue_name, _event, _meta), do: :ok
    def on_event_ok(_exchange_name, _queue_name, _event, _meta, _duration), do: :ok
    def on_event_error(_exchange_name, _queue_name, _event, _meta, _error), do: :ok
    def on_event_retry(_exchange_name, _queue_name, _event, _meta, _error), do: :ok
  end

  defmodule Producer do
    @moduledoc false
    @behaviour Rbt.Instrumentation.Producer

    def setup(_exchange_name), do: :ok
    def teardown(_exchange_name), do: :ok
    def on_connect(_exchange_name), do: :ok
    def on_disconnect(_exchange_name), do: :ok
    def on_publish_ok(_exchange_name, _event, _buffer_size), do: :ok
    def on_publish_error(_exchange_name, _event, _error, _buffer_size), do: :ok
    def on_queue(_exchange_name, _event, _buffer_size), do: :ok
  end

  defmodule Rpc.Client do
    @moduledoc false
    @behaviour Rbt.Instrumentation.Rpc.Client

    def on_rpc_start(_namespace, _correlation_id), do: :ok
    def on_rpc_end(_namespace, _correlation_id, _duration), do: :ok
  end

  defmodule Rpc.Server do
    @moduledoc false
    @behaviour Rbt.Instrumentation.Rpc.Server

    def setup(_namespace), do: :ok
    def teardown(_namespace), do: :ok
    def on_process(_namespace, _duration), do: :ok
    def on_error(_namespace, _reason), do: :ok
  end
end
