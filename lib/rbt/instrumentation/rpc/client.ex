defmodule Rbt.Instrumentation.Rpc.Client do
  @type correlation_id :: String.t()
  @type namespace :: String.t()
  @type duration_in_us :: integer()

  @callback on_rpc_start(namespace, correlation_id) :: :ok
  @callback on_rpc_end(namespace, correlation_id, duration_in_us) :: :ok
end
