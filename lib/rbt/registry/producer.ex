defmodule Rbt.Registry.Producer do
  def via(exchange_name) do
    {:via, Registry, {__MODULE__, exchange_name}}
  end
end
