defmodule Rbt.Instrumentation.Producer do
  @type exchange_name :: String.t()
  @type event :: Rbt.Producer.Event.t()
  @type error :: term()
  @type buffer_size :: non_neg_integer()

  @callback setup(exchange_name) :: :ok
  @callback teardown(exchange_name) :: :ok
  @callback on_connect(exchange_name) :: :ok
  @callback on_disconnect(exchange_name) :: :ok
  @callback on_publish_ok(exchange_name, event, buffer_size) :: :ok
  @callback on_publish_error(exchange_name, event, error, buffer_size) :: :ok
  @callback on_queue(exchange_name, event, buffer_size) :: :ok
end
