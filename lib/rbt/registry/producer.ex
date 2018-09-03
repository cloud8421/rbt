defmodule Rbt.Registry.Producer do
  def child_spec do
    {Registry, keys: :unique, name: Rbt.Registry.Producer}
  end

  def via(exchange_name) do
    {:via, Registry, {__MODULE__, exchange_name}}
  end
end
