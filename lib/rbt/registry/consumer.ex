defmodule Rbt.Registry.Consumer do
  def via(exchange_name, queue_name) do
    {:via, Registry, {__MODULE__, {exchange_name, queue_name}}}
  end
end
