defmodule Rbt.Instrumentation.Rpc.Client do
  @moduledoc """
  A module the implements this behaviour
  can be used to instrument a `Rbt.Client` process.
  """

  @typedoc "A unique id for the rpc call."
  @type correlation_id :: String.t()

  @typedoc """
  The namespace used to identify the pool of servers capable of executing the rpc call.
  """
  @type namespace :: String.t()

  @typedoc """
  The duration of the rpc call in microseconds.
  """
  @type duration_in_us :: integer()

  @doc """
  Called right after the client successfully routed the rpc call.
  """
  @callback on_rpc_start(namespace, correlation_id) :: :ok

  @doc """
  Called when the client receives a response for a pending rpc call.
  """
  @callback on_rpc_end(namespace, correlation_id, duration_in_us) :: :ok
end
