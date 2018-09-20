defmodule Rbt.IntegrationTest do
  use ExUnit.Case, async: false

  defmodule SpyHandler do
    use Rbt.Consumer.Handler
    use GenServer

    def start_link(test_process) do
      GenServer.start_link(__MODULE__, test_process, name: __MODULE__)
    end

    def init(test_process) do
      {:ok, test_process}
    end

    def skip?(%{"case" => "skip"}, _meta) do
      GenServer.call(__MODULE__, :skip)
    end

    def skip?(_event, _meta), do: false

    def handle_event(%{"case" => "success"}, _meta) do
      GenServer.call(__MODULE__, :success)
    end

    def handle_event(%{"case" => "no_retry"}, _meta) do
      GenServer.call(__MODULE__, :no_retry)
    end

    def handle_event(payload, _meta) do
      GenServer.call(__MODULE__, {:unexpected_payload, payload})
    end

    def handle_call(:skip, _from, test_process) do
      send(test_process, :skip)
      {:reply, true, test_process}
    end

    def handle_call(:success, _from, test_process) do
      send(test_process, :success)
      {:reply, :ok, test_process}
    end

    def handle_call(:no_retry, _from, test_process) do
      send(test_process, :no_retry)
      {:reply, {:error, :no_retry, :invalid_data}, test_process}
    end

    def handle_call({:unexpected_payload, payload}, _from, test_process) do
      send(test_process, {:unexpected_payload, payload})
      {:reply, :ok, test_process}
    end
  end

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
        {Rbt.Consumer.Topic,
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
      assert {:ok, :requested} == Rbt.Consumer.Topic.cancel("test-exchange", "test-queue")
      assert :ok == Rbt.Consumer.Topic.cancel("test-exchange", "test-queue")

      # Can try to consume twice
      assert {:ok, :requested} == Rbt.Consumer.Topic.consume("test-exchange", "test-queue")
      assert :ok == Rbt.Consumer.Topic.consume("test-exchange", "test-queue")
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
