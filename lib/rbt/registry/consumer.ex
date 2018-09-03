defmodule Rbt.Registry.Consumer do
  def child_spec do
    {Registry, keys: :unique, name: Rbt.Registry.Consumer}
  end

  def via(exchange_name, queue_name) do
    {:via, Registry, {__MODULE__, {exchange_name, queue_name}}}
  end
end
