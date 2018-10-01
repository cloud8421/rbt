defmodule Rbt.IntegrationTest do
  use ExUnit.Case, async: true

  alias Rbt.SpyHandler

  defmodule ExampleSupervisor do
    use Supervisor

    def start_link(vhost_url) do
      Supervisor.start_link(__MODULE__, vhost_url)
    end

    def init(opts) do
      vhost_url = Keyword.fetch!(opts, :vhost_url)
      test_process = Keyword.fetch!(opts, :test_process)

      children = [
        {SpyHandler, test_process},
        {Rbt.Conn, uri: vhost_url, name: :prod_conn},
        {Rbt.Conn, uri: vhost_url, name: :cons_conn},
        {Rbt.Producer, conn_ref: :prod_conn, definitions: %{exchange_name: "test-exchange"}},
        {Rbt.Consumer,
         conn_ref: :cons_conn,
         handler: SpyHandler,
         definitions: %{
           exchange_name: "test-exchange",
           queue_name: "test-queue",
           routing_keys: ["test.topic"]
         },
         max_retries: 3}
      ]

      Supervisor.init(children, strategy: :one_for_one)
    end
  end

  describe "produce and consume events" do
    setup [:start_tree]

    @tag :integration
    test "selective consume/cancel" do
      Process.sleep(50)
      # Can try to cancel twice
      assert {:ok, :requested} == Rbt.Consumer.cancel("test-exchange", "test-queue")
      assert :ok == Rbt.Consumer.cancel("test-exchange", "test-queue")

      # Can try to consume twice
      assert {:ok, :requested} == Rbt.Consumer.consume("test-exchange", "test-queue")
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
