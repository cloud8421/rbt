defmodule Rbt.Instrumentation.NoOp do
  def on_consume(_exchange_name, _queue_name), do: :ok
  def on_cancel(_exchange_name, _queue_name), do: :ok
end
