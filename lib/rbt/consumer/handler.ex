defmodule Rbt.Consumer.Handler do
  @type event :: term
  @type meta :: map
  @type reason :: term
  @type retry_policy :: :retry | :no_retry

  @callback handle_event(event, meta) :: :ok | {:error, retry_policy, reason}
end
