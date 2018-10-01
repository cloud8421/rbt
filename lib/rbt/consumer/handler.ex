defmodule Rbt.Consumer.Handler do
  @moduledoc """
  The `Rbt.Consumer.Handler` behaviour can be used to model RabbitMQ consumers.

  See the [relevant RabbitMQ tutorial](https://www.rabbitmq.com/tutorials/tutorial-five-elixir.html)
  for the principles behind topic-based consumers.

  To use it:

  ### 1. Define a consumer handler module

  This is done by using the `Rbt.Consumer.Handler` behaviour, which requires implementing a `c:handle_event/2` function (see its docs for more details about its expected return values.

      defmodule MyHandler do
        use Rbt.Consumer.Handler

        def handle_event(event, meta) do
          # do something with the event
          :ok
        end
      end

  ### 2. Prepare your initial configuration

  The consumer will be started with a configuration map that supports quite a few attributes.

  - `definitions`: this is a map which represents the RabbitMQ objects needed by this consumer (exchange, queue and bindings).
  All objects are created automatically when the the consumer is started. Properties in this map are:
    - `exchange_name` (string): the name of the exchange to create/use
    - `queue_name` (string): the name of the queue to create/use
    - `routing_keys` (list of strings): the bindings between the exchange and the queue

  - `durable_objects` (boolean, default `false`): if exchanges and queues will need to be written to disk (so choosing reliability over performance)

  - `max_workers` (integer, default `5`): how many messages this consumer can handle in parallel at any given time. Note that this value will be used to both a) set a prefetch count on the channel, so that RabbitMQ will not deliver a 6th message unless any of the 5 before have been acknowledged b) limit the amount of processes that the consumer can spawn to handle messages to a maximum of 5.

  - `max_retries` (integer or `:infinity`, default `:infinity`): how many times to attempt to process the message before giving up. Note that re-processing happens by rejecting the message and requeuing it, so there's no guarantee that the retry would be picked up by the same consumer instance (in case of a multi-node setup).

  - `forward_failures` (boolean, default `false`): after exhausting retries or encountering a `:no_retry` failure, forward the failed message to an error specific exchange that a user can bind on. This is accomplished via dead letter exchange headers, so it's controlled at the queue declaration level. To know more about this: <https://www.rabbitmq.com/dlx.html>.

  ### 3. Start a consumer in the Supervision tree

  Given a defined handler, this is a minimum setup:

      consumer_config = %{
        handler: MyHandler,
        definitions: %{
          exchange_name: "test-exchange",
          queue_name: "test-queue",
          routing_keys: ["test.topic"]
        },
        max_retries: 3
      }

      children = [
        {Rbt.Consumer, consumer_config}
      ]

  For more details on the consumer itself, see `Rbt.Consumer`.
  """

  @typedoc """
  An event can be any serializable term (see `Rbt.Data` for details
  on what's supported out of the box, but a map is recommended to improve
  management of backwards compatibility.
  """
  @type event :: term

  @typedoc """
  Metadata for incoming messages, in form of a map.
  """
  @type meta :: map
  @type reason :: term
  @type retry_policy :: :retry | :no_retry

  @callback handle_event(event, meta) :: :ok | {:error, retry_policy, reason}

  defmacro __using__(_opts) do
    quote do
      alias Rbt.Consumer.Handler
      @behaviour Handler

      @spec skip?(Handler.event(), Handler.meta()) :: boolean()
      def skip?(_event, _meta), do: false

      defoverridable skip?: 2
    end
  end
end
