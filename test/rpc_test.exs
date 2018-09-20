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
        {Rbt.Conn, uri: vhost_url, name: :rpc_server_conn},
        {Rbt.Conn, uri: vhost_url, name: :rpc_client_conn},
        {Rbt.Rpc.Server,
         conn_ref: :rpc_server_conn, namespace: "rbt-rpc-server-test", config: %{max_workers: 20}},
        {Rbt.Rpc.Client, conn_ref: :rpc_client_conn, name: RpcClient}
      ]

      Supervisor.init(children, strategy: :one_for_one)
    end
  end

  setup [:start_tree, :warm_up]

  test "ok result" do
    assert {:rpc_ok, "A"} =
             Rbt.Rpc.Client.call(RpcClient, "rbt-rpc-server-test", {String, :upcase, ["a"]}, 5000)
  end

  test "exception result" do
    assert {:rpc_error, "no function clause matching in String.upcase/2"} =
             Rbt.Rpc.Client.call(RpcClient, "rbt-rpc-server-test", {String, :upcase, [1]}, 5000)
  end

  test "supports concurrent requests" do
    spec = fn i ->
      {Kernel, :+, [i, 1]}
    end

    parallel_rpc_call(RpcClient, "rbt-rpc-server-test", spec, 500)
    |> Enum.each(fn {i, result} ->
      assert {:rpc_ok, i + 1} == result
    end)
  end

  defp start_tree(_config) do
    opts = [
      vhost_url: vhost_url()
    ]

    start_supervised!({ExampleSupervisor, opts})

    :ok
  end

  defp warm_up(_config) do
    Process.sleep(200)
    :ok
  end

  defp vhost_url do
    "amqp://guest:guest@localhost:5672/rbt-test"
  end

  defp parallel_rpc_call(client_ref, namespace, spec, repetitions) do
    1..repetitions
    |> Enum.shuffle()
    |> Enum.map(fn i ->
      task =
        Task.async(fn ->
          Rbt.Rpc.Client.call(client_ref, namespace, spec.(i), 5000)
        end)

      {i, task}
    end)
    |> Enum.map(fn {i, task} -> {i, Task.await(task)} end)
  end
end
