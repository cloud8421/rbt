defmodule Rbt.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [
      {Registry, keys: :unique, name: Registry.Rbt.Consumer}
    ]

    opts = [strategy: :one_for_one, name: Rbt.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
