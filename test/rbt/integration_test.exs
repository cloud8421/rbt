defmodule Rbt.IntegrationTest do
  use ExUnit.Case, async: true

  alias Rbt.Spy

  defmodule ExampleSupervisor do
    use Supervisor

    def start_link(vhost_url) do
      Supervisor.start_link(__MODULE__, vhost_url)
    end

    def init(opts) do
      vhost_url = Keyword.fetch!(opts, :vhost_url)
      test_process = Keyword.fetch!(opts, :test_process)

      children = [
        {Spy.Handler, test_process},
        {Spy.Instrumenter.Consumer, test_process},
        {Rbt.Conn, uri: vhost_url, name: :prod_conn},
        {Rbt.Conn, uri: vhost_url, name: :cons_conn},
        {Rbt.Producer, conn_ref: :prod_conn, definitions: %{exchange_name: "test-exchange"}},
        {Rbt.Consumer,
         conn_ref: :cons_conn,
         handler: Spy.Handler,
         definitions: %{
           exchange_name: "test-exchange",
           queue_name: "test-queue",
           routing_keys: ["test.topic"]
         },
         create_infrastructure: true,
         max_retries: 3,
         instrumentation: Spy.Instrumenter.Consumer}
      ]

      Supervisor.init(children, strategy: :one_for_one)
    end
  end

  describe "produce and consume events" do
    setup [:start_tree]

    @tag :integration
    test "selective consume/cancel" do
      assert_receive {:on_consume, _params}
      # Can try to cancel twice
      assert {:ok, :requested} == Rbt.Consumer.cancel("test-exchange", "test-queue")
      assert_receive {:on_cancel, _params}
      assert :ok == Rbt.Consumer.cancel("test-exchange", "test-queue")

      # Can try to consume twice
      assert {:ok, :requested} == Rbt.Consumer.consume("test-exchange", "test-queue")
      assert_receive {:on_consume, _params}
      assert :ok == Rbt.Consumer.consume("test-exchange", "test-queue")
    end

    @tag :integration
    test "publish and consume success" do
      :ok =
        Rbt.Producer.publish(
          "test-exchange",
          "test.topic",
          %{case: "success"},
          content_type: "application/json"
        )

      assert_receive :success
    end

    @tag :integration
    test "publish and consume error" do
      :ok =
        Rbt.Producer.publish(
          "test-exchange",
          "test.topic",
          %{case: "no_retry"},
          content_type: "application/json"
        )

      assert_receive :no_retry
    end

    @tag :integration
    test "publish and skip" do
      :ok =
        Rbt.Producer.publish(
          "test-exchange",
          "test.topic",
          %{case: "skip"},
          content_type: "application/json"
        )

      assert_receive :skip
    end
  end

  defp start_tree(_config) do
    opts = [
      vhost_url: vhost_url(),
      test_process: self()
    ]

    start_supervised!({ExampleSupervisor, opts})

    :ok
  end

  defp vhost_url do
    "amqp://guest:guest@localhost:5672/rbt-test"
  end
end
