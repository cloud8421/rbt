defmodule Rbt.Instrumentation.NoOp do
  def setup(_exchange_name, _queue_name), do: :ok
  def teardown(_exchange_name, _queue_name), do: :ok
  def on_consume(_exchange_name, _queue_name), do: :ok
  def on_cancel(_exchange_name, _queue_name), do: :ok
  def on_event_skip(_exchange_name, _queue_name, _event, _meta), do: :ok
  def on_event_ok(_exchange_name, _queue_name, _event, _meta), do: :ok
  def on_event_error(_exchange_name, _queue_name, _event, _meta, _error), do: :ok
end
