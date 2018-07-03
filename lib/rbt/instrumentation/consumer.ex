defmodule Rbt.Instrumentation.Consumer do
  @type exchange_name :: String.t()
  @type queue_name :: String.t()
  @type event :: term()
  @type meta :: term()
  @type error :: term()

  @callback setup(exchange_name, queue_name) :: :ok
  @callback teardown(exchange_name, queue_name) :: :ok
  @callback on_consume(exchange_name, queue_name) :: :ok
  @callback on_event_skip(exchange_name, queue_name, event, meta) :: :ok
  @callback on_event_ok(exchange_name, queue_name, event, meta) :: :ok
  @callback on_event_error(exchange_name, queue_name, event, meta, error) :: :ok
end
