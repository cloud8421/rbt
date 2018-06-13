defmodule Rbt.Consumer.Deliver do
  def handle(payload, meta, consumer_config) do
    case Rbt.Parser.decode(payload, meta.content_type) do
      {:ok, decoded} ->
        try_handle_event(decoded, meta, consumer_config.handler)

      error ->
        error
    end
  end

  defp try_handle_event(event, meta, handler) do
    try do
      handler.handle_event(event, meta)
    rescue
      error ->
        {:error, :retry, error}
    catch
      error ->
        {:error, :retry, error}

      _exit, reason ->
        {:error, :retry, reason}
    end
  end
end
