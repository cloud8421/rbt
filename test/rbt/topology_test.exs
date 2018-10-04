defmodule Rbt.TopologyTest do
  use ExUnit.Case, async: true

  defmodule ExampleSupervisor do
    use Supervisor

    def start_link(vhost_url) do
      Supervisor.start_link(__MODULE__, vhost_url)
    end

    def init(opts) do
      vhost_url = Keyword.fetch!(opts, :vhost_url)

      children = [
        {Rbt.Conn, uri: vhost_url, name: :topo_prod_conn},
        {Rbt.Conn, uri: vhost_url, name: :topo_cons_conn},
        {Rbt.Conn, uri: vhost_url, name: :topo_rpc_server_conn},
        {Rbt.Conn, uri: vhost_url, name: :topo_rpc_client_conn},
        {Rbt.Rpc.Server,
         conn_ref: :topo_rpc_server_conn,
         namespace: "rbt-topo-rpc-server-test",
         config: %{max_workers: 20}},
        {Rbt.Rpc.Client, conn_ref: :topo_rpc_client_conn, name: TopoClient},
        {Rbt.Producer,
         conn_ref: :topo_prod_conn, definitions: %{exchange_name: "topo-test-exchange"}},
        {Rbt.Consumer,
         conn_ref: :topo_cons_conn,
         handler: NoOpHandler,
         definitions: %{
           exchange_name: "topo-test-exchange",
           queue_name: "topo-test-queue",
           routing_keys: ["topo-test.topic"]
         },
         create_infrastructure: true,
         max_retries: 3}
      ]

      Supervisor.init(children, strategy: :one_for_one)
    end
  end

  describe "runtime topology" do
    setup [:start_tree]

    @tag :integration
    test "returns all data", %{sup: sup} do
      assert %{
               Rbt.Conn => [
                 %{name: :topo_prod_conn, state: :connected},
                 %{name: :topo_cons_conn, state: :connected},
                 %{name: :topo_rpc_server_conn, state: :connected},
                 %{name: :topo_rpc_client_conn, state: :connected}
               ],
               Rbt.Consumer => [
                 %{
                   config: %{forward_failures: false, max_retries: 3, max_workers: 5},
                   conn_ref: :topo_cons_conn,
                   infrastructure: %{
                     exchange_name: "topo-test-exchange",
                     queue_name: "topo-test-queue",
                     routing_keys: ["topo-test.topic"]
                   },
                   state: :subscribing
                 }
               ],
               Rbt.Producer => [
                 %{
                   config: %{exchange_type: :topic},
                   conn_ref: :topo_prod_conn,
                   infrastructure: %{exchange_name: "topo-test-exchange"},
                   state: :active
                 }
               ],
               Rbt.Rpc.Client => [
                 %{
                   conn_ref: :topo_rpc_client_conn,
                   pending: 0,
                   queue_name: _queue_name,
                   state: :subscribed
                 }
               ],
               Rbt.Rpc.Server => [
                 %{
                   conn_ref: :topo_rpc_server_conn,
                   max_workers: 20,
                   namespace: "rbt-topo-rpc-server-test",
                   state: :ready
                 }
               ]
             } = Rbt.Topology.for_supervisor(sup)
    end
  end

  defp start_tree(_config) do
    opts = [
      vhost_url: vhost_url()
    ]

    sup = start_supervised!({ExampleSupervisor, opts})

    [sup: sup]
  end

  defp vhost_url do
    "amqp://guest:guest@localhost:5672/rbt-test"
  end
end
