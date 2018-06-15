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
      if handler.skip?(event, meta) do
        {:skip, event}
      else
        do_try_handle_event(event, meta, handler)
      end
    rescue
      error ->
        {:error, :retry, error, event}
    catch
      error ->
        {:error, :retry, error, event}

      _exit, reason ->
        {:error, :retry, reason, event}
    end
  end

  defp do_try_handle_event(event, meta, handler) do
    case handler.handle_event(event, meta) do
      :ok ->
        {:ok, event}

      error ->
        Tuple.append(error, event)
    end
  end
end
