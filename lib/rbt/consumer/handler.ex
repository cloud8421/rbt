defmodule Rbt.Consumer.Handler do
  @type event :: term
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
