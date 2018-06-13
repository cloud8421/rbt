defmodule Rbt.Parser do
  @json_adapter Application.get_env(:rbt, :json_adapter, Jason)

  def decode(payload, "application/json") do
    @json_adapter.decode(payload)
  end

  def decode(payload, "application/octet-stream") do
    {:ok, :erlang.binary_to_term(payload, [:safe])}
  end

  def decode(_payload, _content_type) do
    {:error, :unsupported_content_type}
  end
end
