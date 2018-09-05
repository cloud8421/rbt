defmodule Rbt.RpcTest do
  use ExUnit.Case, async: true

  defmodule ExampleSupervisor do
    use Supervisor

    def start_link(vhost_url) do
      Supervisor.start_link(__MODULE__, vhost_url)
    end

    def init(opts) do
      vhost_url = Keyword.fetch!(opts, :vhost_url)

      children = [
        Rbt.Conn.child_spec(uri: vhost_url, name: :rpc_server_conn),
        Rbt.Rpc.Server.child_spec(
          conn_ref: :rpc_server_conn,
          namespace: "rbt-rpc-server-test"
        )
      ]

      Supervisor.init(children, strategy: :one_for_one)
    end
  end

  setup :start_tree

  test "it works" do
    Process.sleep(500)
  end

  defp start_tree(_config) do
    opts = [
      vhost_url: vhost_url()
    ]

    start_supervised!({ExampleSupervisor, opts})

    :ok
  end

  defp vhost_url do
    "amqp://guest:guest@localhost:5672/rbt-test"
  end
end
