defmodule Rbt.Producer.Sandbox do
  @moduledoc """
  Provides a Sandbox producer which can be used in tests (the API is
  compatible with `Rbt.Producer`.

  The sandbox purpose is to provide a in-memory, concurrency-safe way to
  produce events and verify their existence.

  Each event is stored in a public ets table and it includes information about
  the pid that produced it.

  Note a pid referenced by the Sandbox is not garbage collected once
  the corresponding process dies. This is to allow inspection of produced events
  after their origin has disappeared.
  """
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

  def count_by_exchange(exchange_name, producer_pid \\ self()) do
    spec = [{{:_, exchange_name, :_, producer_pid, :"$1"}, [], [true]}]

    :ets.select_count(__MODULE__, spec)
  end

  def find_by_exchange_and_topic(exchange_name, topic, producer_pid \\ self()) do
    spec = [{{:_, exchange_name, topic, producer_pid, :"$1"}, [], [:"$1"]}]

    :ets.select(__MODULE__, spec)
  end

  def count_by_exchange_and_topic(exchange_name, topic, producer_pid \\ self()) do
    spec = [{{:_, exchange_name, topic, producer_pid, :"$1"}, [], [true]}]

    :ets.select_count(__MODULE__, spec)
  end

  def find_by_producer_pid(producer_pid) do
    spec = [{{:_, :_, :_, producer_pid, :"$1"}, [], [:"$1"]}]

    :ets.select(__MODULE__, spec)
  end

  def count_by_producer_pid(producer_pid) do
    spec = [{{:_, :_, :_, producer_pid, :"$1"}, [], [true]}]

    :ets.select_count(__MODULE__, spec)
  end

  defp store(exchange_name, event, publisher_pid) do
    record = {event.message_id, exchange_name, event.topic, publisher_pid, event}
    true = :ets.insert(__MODULE__, record)
    :ok
  end
end
