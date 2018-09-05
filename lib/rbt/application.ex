defmodule Rbt.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [
      Rbt.Registry.Consumer.child_spec(),
      Rbt.Registry.Producer.child_spec(),
      {Task.Supervisor, name: Rbt.Consumer.DefaultTaskSupervisor},
      {Task.Supervisor, name: Rbt.Rpc.DefaultTaskSupervisor}
    ]

    opts = [strategy: :one_for_one, name: Rbt.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
