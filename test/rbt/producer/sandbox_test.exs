defmodule Rbt.Producer.SandboxTest do
  use ExUnit.Case, async: true

  alias Rbt.Producer.Sandbox

  setup_all :create_table

  test "can publish" do
    assert :ok == publish_sample_event()
  end

  test "lookup by exchange, pid implied" do
    exchange_name = Rbt.UUID.generate()
    :ok = publish_sample_event(exchange_name)
    assert [event] = Sandbox.find_by_exchange(exchange_name)
    assert event.data == %{some: "data"}
  end

  test "lookup by exchange and topic, pid implied" do
    exchange_name = Rbt.UUID.generate()
    topic = Rbt.UUID.generate()
    :ok = publish_sample_event(exchange_name, topic)
    :ok = publish_sample_event(exchange_name, topic <> "2")
    assert [event] = Sandbox.find_by_exchange_and_topic(exchange_name, topic)
    assert event.data == %{some: "data"}
  end

  test "lookup by pid" do
    :ok = publish_sample_event()

    assert [event] = Sandbox.find_by_producer_pid(self())
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
