defmodule Rbt.Instrumentation.Rpc.Server do
  @moduledoc """
  A module the implements this behaviour
  can be used to instrument a `Rbt.Server` process.
  """

  @typedoc """
  The namespace used to identify the pool of servers capable of executing the rpc call.
  """
  @type namespace :: String.t()

  @typedoc """
  The duration of the rpc call in microseconds.
  """
  @type duration_in_us :: integer()

  @typedoc "The reason for the error"
  @type reason :: term()

  @doc """
  Called when the rpc server is booted. Can be used
  to create a metric store if needed.
  """
  @callback setup(namespace) :: :ok

  @doc """
  Called when the rpc server is stopped. Can be used
  to perform any necessary cleanup.
  """
  @callback teardown(namespace) :: :ok

  @doc """
  Called after the rpc server has executed an rpc call and published
  its reply.
  """
  @callback on_process(namespace, duration_in_us) :: :ok

  @doc """
  Called when the rpc server errors in executing the rpc call.
  """
  @callback on_error(namespace, reason) :: :ok
end
