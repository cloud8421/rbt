defmodule Rbt.ProducerTest do
  use ExUnit.Case, async: true

  alias Rbt.Spy

  @rmq_test_url "amqp://guest:guest@localhost:5672/rbt-test"

  test "resilience test" do
    {:ok, conn} = Rbt.Conn.start_link(@rmq_test_url, [], __MODULE__)
    {:ok, _pid} = Spy.Instrumenter.Producer.start_link(self())

    {:ok, pid} =
      Rbt.Producer.start_link(__MODULE__, %{
        exchange_name: "producer-exchange",
        instrumentation: Spy.Instrumenter.Producer
      })

    ref = Process.monitor(pid)
    refute_receive {:DOWN, ^ref, :process, ^pid, _reason}, 300

    publish_sample_message(2)

    assert_receive {:on_publish_ok, _params}
    assert_receive {:on_publish_ok, _params}

    assert :active == Rbt.Producer.status("producer-exchange").state
    assert :active == Rbt.Producer.status(pid).state

    # active connection, buffer remains empty

    assert 0 == Rbt.Producer.buffer_size("producer-exchange")
    assert 0 == Rbt.Producer.buffer_size(pid)
    assert [] == Rbt.Producer.buffer(pid)

    Rbt.Conn.close(conn)

    publish_sample_message(3)

    assert_receive {:on_queue, _params}
    assert_receive {:on_queue, _params}
    assert_receive {:on_queue, _params}

    assert :buffering == Rbt.Producer.status("producer-exchange").state
    assert :buffering == Rbt.Producer.status(pid).state

    # broken connection, buffer fills up

    assert 3 == Rbt.Producer.buffer_size("producer-exchange")
    assert 3 == Rbt.Producer.buffer_size(pid)

    {:ok, _conn} = Rbt.Conn.start_link(@rmq_test_url, [], __MODULE__)

    publish_sample_message(1)

    # connection is warming up (in backoff mode), buffer keeps filling up

    assert 4 == Rbt.Producer.buffer_size("producer-exchange")
    assert 4 == Rbt.Producer.buffer_size(pid)

    publish_sample_message(100)

    Enum.each(1..100, fn _ ->
      assert_receive {:on_publish_ok, _params}, 200
    end)

    assert :active == Rbt.Producer.status("producer-exchange").state
    assert :active == Rbt.Producer.status(pid).state

    # connection active, buffer gets emptied

    assert 0 == Rbt.Producer.buffer_size("producer-exchange")
    assert 0 == Rbt.Producer.buffer_size(pid)
    assert [] == Rbt.Producer.buffer("producer-exchange")
    assert [] == Rbt.Producer.buffer(pid)

    assert :ok == Rbt.Producer.stop(pid)
  end

  defp publish_sample_message(number_of_times) do
    Enum.each(1..number_of_times, fn _ ->
      assert :ok ==
               Rbt.Producer.publish(
                 "producer-exchange",
                 "test.topic",
                 %{some: "data"},
                 content_type: "application/json"
               )
    end)
  end
end
