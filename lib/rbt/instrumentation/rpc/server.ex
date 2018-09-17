defmodule Rbt.Instrumentation.Rpc.Server do
  @type namespace :: String.t()
  @type duration_in_us :: integer()
  @type reason :: term()

  @callback setup(namespace) :: :ok
  @callback teardown(namespace) :: :ok
  @callback on_process(namespace, duration_in_us) :: :ok
  @callback on_error(namespace, reason) :: :ok
end
