defmodule Rbt.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [
      {Registry, keys: :unique, name: Rbt.Registry.Consumer},
      {Registry, keys: :unique, name: Rbt.Registry.Producer},
      {Task.Supervisor, name: Rbt.Consumer.DefaultTaskSupervisor}
    ]

    opts = [strategy: :one_for_one, name: Rbt.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
