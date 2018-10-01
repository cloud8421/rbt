defmodule Rbt.Binding do
  @moduledoc """
  Define bindings between RabbitMQ objects.
  """

  @type exchange_name :: String.t()
  @type queue_name :: String.t()
  @type routing_key :: String.t()
  @type bind_opts :: Keyword.t()

  @doc """
  Declares a binding between two exchanges.
  """
  @spec exchange_to_exchange(
          Rbt.Conn.name(),
          exchange_name,
          exchange_name,
          routing_key,
          bind_opts
        ) :: :ok | no_return()
  def exchange_to_exchange(conn_name, source, destination, routing_key, options \\ []) do
    {:ok, channel} = Rbt.Channel.open(conn_name)

    AMQP.Exchange.bind(
      channel,
      destination,
      source,
      Keyword.merge([routing_key: routing_key], options)
    )

    Rbt.Channel.close(channel)
  end

  @doc """
  Declares a binding between an exchange and a queue.
  """
  @spec exchange_to_queue(Rbt.Conn.name(), exchange_name, queue_name, routing_key, bind_opts) ::
          :ok | no_return()
  def exchange_to_queue(conn_name, source, destination, routing_key, options \\ []) do
    {:ok, channel} = Rbt.Channel.open(conn_name)

    AMQP.Queue.bind(
      channel,
      destination,
      source,
      Keyword.merge([routing_key: routing_key], options)
    )

    Rbt.Channel.close(channel)
  end
end
