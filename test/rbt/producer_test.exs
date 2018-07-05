defmodule Rbt.ProducerTest do
  use ExUnit.Case, async: true

  @rmq_test_url "amqp://guest:guest@localhost:5672/rbt-test"

  test "resilience test" do
    {:ok, conn} = Rbt.Conn.start_link(@rmq_test_url, [], __MODULE__)

    {:ok, pid} = Rbt.Producer.start_link(__MODULE__, %{exchange_name: "test-exchange"})
    ref = Process.monitor(pid)
    refute_receive {:DOWN, ^ref, :process, ^pid, _reason}, 300

    publish_sample_message(2)

    # active connection, buffer remains empty

    assert 0 == Rbt.Producer.buffer_size(pid)
    assert [] == Rbt.Producer.buffer(pid)

    Rbt.Conn.close(conn)

    publish_sample_message(3)

    # broken connection, buffer fills up

    assert 3 == Rbt.Producer.buffer_size(pid)

    {:ok, _conn} = Rbt.Conn.start_link(@rmq_test_url, [], __MODULE__)

    publish_sample_message(1)

    # connection is warming up (in backoff mode), buffer keeps filling up

    assert 4 == Rbt.Producer.buffer_size(pid)

    publish_sample_message(100)

    Process.sleep(100)

    # connection active, buffer gets emptied

    assert 0 == Rbt.Producer.buffer_size(pid)
    assert [] == Rbt.Producer.buffer(pid)
  end

  defp publish_sample_message(number_of_times) do
    Enum.each(1..number_of_times, fn _ ->
      assert :ok ==
               Rbt.Producer.publish(
                 "test-exchange",
                 "test.topic",
                 %{some: "data"},
                 content_type: "application/json"
               )
    end)
  end
end
