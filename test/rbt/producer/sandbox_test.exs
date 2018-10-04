defmodule Rbt.Producer.SandboxTest do
  use ExUnit.Case, async: true

  alias Rbt.Producer.Sandbox

  setup_all :create_table

  test "can publish" do
    assert :ok == publish_sample_event()
  end

  describe "lookup/count by exchange" do
    test "with implicit caller pid" do
      exchange_name = Rbt.UUID.generate()
      :ok = publish_sample_event(exchange_name)

      assert [event] = Sandbox.find_by_exchange(exchange_name)
      assert 1 == Sandbox.count_by_exchange(exchange_name)
      assert event.data == %{some: "data"}
    end

    test "with explicit pid" do
      exchange_name = Rbt.UUID.generate()
      caller = self()

      pid =
        spawn(fn ->
          :ok = publish_sample_event(exchange_name)
          send(caller, :done)
        end)

      assert_receive :done, 200
      assert [] == Sandbox.find_by_exchange(exchange_name)
      assert 0 == Sandbox.count_by_exchange(exchange_name)
      assert [event] = Sandbox.find_by_exchange(exchange_name, pid)
      assert 1 == Sandbox.count_by_exchange(exchange_name, pid)
      assert event.data == %{some: "data"}
    end
  end

  describe "lookup/count by exchange and topic" do
    test "with implicit pid" do
      exchange_name = Rbt.UUID.generate()
      topic = Rbt.UUID.generate()
      :ok = publish_sample_event(exchange_name, topic)
      :ok = publish_sample_event(exchange_name, topic <> "2")
      assert [event] = Sandbox.find_by_exchange_and_topic(exchange_name, topic)
      assert 1 == Sandbox.count_by_exchange_and_topic(exchange_name, topic)
      assert event.data == %{some: "data"}
    end

    test "with explicit pid" do
      exchange_name = Rbt.UUID.generate()
      topic = Rbt.UUID.generate()
      caller = self()

      pid =
        spawn(fn ->
          :ok = publish_sample_event(exchange_name, topic)
          :ok = publish_sample_event(exchange_name, topic <> "2")
          send(caller, :done)
        end)

      assert_receive :done, 200
      assert [] == Sandbox.find_by_exchange_and_topic(exchange_name, topic)
      assert 0 == Sandbox.count_by_exchange_and_topic(exchange_name, topic)
      assert [] == Sandbox.find_by_exchange_and_topic(exchange_name, topic <> "2")
      assert 0 == Sandbox.count_by_exchange_and_topic(exchange_name, topic <> "2")
      assert [_event] = Sandbox.find_by_exchange_and_topic(exchange_name, topic <> "2", pid)
      assert 1 == Sandbox.count_by_exchange_and_topic(exchange_name, topic <> "2", pid)
      assert [event] = Sandbox.find_by_exchange_and_topic(exchange_name, topic, pid)
      assert 1 == Sandbox.count_by_exchange_and_topic(exchange_name, topic, pid)
      assert event.data == %{some: "data"}
    end
  end

  test "lookup/count by pid" do
    :ok = publish_sample_event()

    assert [event] = Sandbox.find_by_producer_pid(self())
    assert 1 == Sandbox.count_by_producer_pid(self())
    assert event.data == %{some: "data"}
  end

  defp create_table(_config) do
    Sandbox.create_table!()
    :ok
  end

  defp publish_sample_event(exchange_name \\ "test-exchange", topic \\ "test-topic") do
    Sandbox.publish(
      exchange_name,
      topic,
      %{some: "data"},
      content_type: "application/json"
    )
  end
end
