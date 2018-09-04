defmodule Rbt.Producer.Sandbox do
  alias Rbt.Producer.Event

  def create_table! do
    opts = [
      :named_table,
      :public
    ]

    __MODULE__ = :ets.new(__MODULE__, opts)
  end

  def publish(exchange_name, topic, event_data, opts) do
    publisher_pid = self()
    message_id = Keyword.get(opts, :message_id, Rbt.UUID.generate())

    event_opts = [
      content_type: Keyword.fetch!(opts, :content_type),
      persistent: Keyword.get(opts, :persistent, false)
    ]

    event = Event.new(message_id, topic, event_data, event_opts)
    store(exchange_name, event, publisher_pid)
  end

  def find_by_exchange(exchange_name, producer_pid \\ self()) do
    spec = [{{:_, exchange_name, :_, producer_pid, :"$1"}, [], [:"$1"]}]

    :ets.select(__MODULE__, spec)
  end

  def find_by_exchange_and_topic(exchange_name, topic, producer_pid \\ self()) do
    spec = [{{:_, exchange_name, topic, producer_pid, :"$1"}, [], [:"$1"]}]

    :ets.select(__MODULE__, spec)
  end

  def find_by_producer_pid(producer_pid) do
    spec = [{{:_, :_, :_, producer_pid, :"$1"}, [], [:"$1"]}]

    :ets.select(__MODULE__, spec)
  end

  defp store(exchange_name, event, publisher_pid) do
    record = {event.message_id, exchange_name, event.topic, publisher_pid, event}
    true = :ets.insert(__MODULE__, record)
    :ok
  end
end
