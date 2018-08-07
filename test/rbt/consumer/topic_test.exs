defmodule Rbt.Consumer.TopicTest do
  use ExUnit.Case, async: false

  @rmq_test_url "amqp://guest:guest@localhost:5672/rbt-test"

  defmodule Foo do
    use Rbt.Consumer.Handler

    def skip?(%{"should" => "skip"}, _meta), do: true
    def skip?(_event, _meta), do: false

    def handle_event(%{"should" => "ok"}, _meta) do
      :ok
    end

    def handle_event(%{"should" => "no_retry"}, _meta) do
      {:error, :no_retry, :invalid_data}
    end

    def handle_event(%{"should" => "bomb"}, _meta) do
      raise "runtime error doh!"
    end

    def handle_event(_message, _meta) do
      :ok
    end
  end

  test "integration" do
    handler = Foo

    config = %{
      definitions: %{
        exchange_name: "test-exchange",
        queue_name: "test-queue",
        routing_keys: ["test.topic"]
      },
      max_retries: 3
    }

    {:ok, _cons_conn} = Rbt.Conn.start_link(@rmq_test_url, [], :cons_conn)
    {:ok, _prod_conn} = Rbt.Conn.start_link(@rmq_test_url, [], :prod_conn)

    {:ok, cons_pid} = Rbt.Consumer.Topic.start_link(:cons_conn, handler, config)
    ref = Process.monitor(cons_pid)
    refute_receive {:DOWN, ^ref, :process, ^cons_pid, _reason}, 300

    {:ok, :requested} = Rbt.Consumer.Topic.cancel("test-exchange", "test-queue")
    :ok = Rbt.Consumer.Topic.cancel("test-exchange", "test-queue")

    {:ok, :requested} = Rbt.Consumer.Topic.consume("test-exchange", "test-queue")
    :ok = Rbt.Consumer.Topic.consume("test-exchange", "test-queue")

    {:ok, prod_pid} = Rbt.Producer.start_link(:prod_conn, %{exchange_name: "test-exchange"})
    ref = Process.monitor(prod_pid)
    refute_receive {:DOWN, ^ref, :process, ^prod_pid, _reason}, 300

    Rbt.Producer.publish(
      "test-exchange",
      "test.topic",
      %{should: "ok"},
      content_type: "application/json"
    )

    Rbt.Producer.publish(
      "test-exchange",
      "test.topic",
      %{should: "no_retry"},
      content_type: "application/json"
    )

    Rbt.Producer.publish(
      "test-exchange",
      "test.topic",
      %{should: "skip"},
      content_type: "application/json"
    )

    Rbt.Producer.publish(
      "test-exchange",
      "test.topic",
      %{should: "bomb"},
      content_type: "application/json"
    )

    Process.sleep(500)
  end
end
