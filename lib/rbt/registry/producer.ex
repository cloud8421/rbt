defmodule Rbt.Registry.Producer do
  @moduledoc false

  def child_spec do
    {Registry, keys: :unique, name: __MODULE__}
  end

  def via(exchange_name) do
    {:via, Registry, {__MODULE__, exchange_name}}
  end
end
