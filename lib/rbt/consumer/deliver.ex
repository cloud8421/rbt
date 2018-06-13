defmodule Rbt.Consumer.Deliver do
  @json_adapter Application.get_env(:rbt, :json_adapter, Jason)

  def handle(payload, meta, consumer_config) do
    case decode(payload, meta) do
      {:ok, decoded} ->
        try_handle_event(decoded, meta, consumer_config.handler)

      error ->
        error
    end
  end

  def decode(payload, meta) do
    case meta.content_type do
      "application/json" -> @json_adapter.decode(payload)
      "application/octet-stream" -> safe_erl_decode(payload)
      _unknown -> {:error, :invalid_content_type}
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

  defp safe_erl_decode(payload) do
    {:ok, :erlang.binary_to_term(payload, [:safe])}
  end
end
