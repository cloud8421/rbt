defmodule Rbt.ConsumerTest do
  use ExUnit.Case, async: true

  test "boots and stays up" do
    handler = Foo

    config = %{
      definitions: %{
        exchange_name: "test-exchange",
        queue_name: "test-queue",
        routing_keys: ["foo.bar", "bar.baz"]
      }
    }

    {:ok, conn} = Rbt.Conn.start_link("amqp://guest:guest@localhost:5672/rbt-test", [], :example)

    {:ok, pid} = Rbt.Consumer.start_link(conn, handler, config)
    ref = Process.monitor(pid)
    refute_receive {:DOWN, ^ref, :process, ^pid, _reason}, 300

    {:ok, :requested} = Rbt.Consumer.cancel("test-exchange", "test-queue")
    :ok = Rbt.Consumer.cancel("test-exchange", "test-queue")

    {:ok, :requested} = Rbt.Consumer.consume("test-exchange", "test-queue")
    :ok = Rbt.Consumer.consume("test-exchange", "test-queue")
  end
end
