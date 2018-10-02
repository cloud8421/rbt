defmodule Rbt.Data do
  @moduledoc """
  Provides encoding/decoding functionality for RabbitMQ messages.

  Supports the following content types:

  #### `application/octet-stream`

  Uses `:erlang.term_to_binary/2` and `:erlang.binary_to_term/2` in `safe` mode)

  #### `application/json`

  Uses an optional json adapter module, which can be configured with:

      config :rbt, :json_adapter, MyModule

  Uses [Jason](https://hex.pm/packages/jason) by default.

  The adapter needs to expose `decode/1` and `encode/1` functions.  In both
  instances, the expected return values are either `{:ok, result}` or `{:error,
  reason}`.
  """

  @json_adapter Application.get_env(:rbt, :json_adapter, Jason)

  @typedoc "The payload as delivered via a RabbitMQ channel"
  @type encoded_payload :: binary()

  @typedoc "The payload before being encoded to be published"
  @type decoded_payload :: term()

  @typedoc "The content type used to encode the message. See the module doc for details."
  @type content_type :: String.t()

  @doc """
  Decodes a payload given a supported content type.
  """
  @spec decode(encoded_payload(), content_type()) :: {:ok, decoded_payload()} | {:error, term()}
  def decode(payload, content_type)

  def decode(payload, "application/json") do
    @json_adapter.decode(payload)
  end

  def decode(payload, "application/octet-stream") do
    try do
      {:ok, :erlang.binary_to_term(payload, [:safe])}
    rescue
      ArgumentError -> {:error, :bad_arg}
    end
  end

  def decode(_payload, _content_type) do
    {:error, :unsupported_content_type}
  end

  @doc """
  Decodes a payload given a supported content type, raising an exception
  in case of malformed data.
  """
  @spec decode!(encoded_payload(), content_type()) :: decoded_payload() | no_return()
  def decode!(payload, content_type) do
    {:ok, decoded} = decode(payload, content_type)
    decoded
  end

  @doc """
  Encodes a payload given a supported content type.
  """
  @spec encode(decoded_payload(), content_type()) :: {:ok, encoded_payload()} | {:error, term()}
  def encode(payload, content_type)

  def encode(payload, "application/json") do
    @json_adapter.encode(payload)
  end

  def encode(payload, "application/octet-stream") do
    {:ok, :erlang.term_to_binary(payload, [:compressed])}
  end

  def encode(_payload, _content_type) do
    {:error, :unsupported_content_type}
  end

  @doc """
  Encodes a payload given a supported content type, raising an exception
  in case of malformed data.
  """
  @spec encode!(decoded_payload(), content_type()) :: encoded_payload() | no_return()
  def encode!(payload, content_type) do
    {:ok, encoded} = encode(payload, content_type)
    encoded
  end
end
