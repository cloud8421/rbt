defmodule Rbt.Conn.URI do
  @moduledoc """
  This module can be used to validate and manipulate AMQP URIs
  as specified at <https://www.rabbitmq.com/uri-spec.html>.
  """

  @typedoc "A RabbitMQ server uri in string form"
  @type t :: String.t()

  @doc """
  Validates a uri. Please refer to `amqp_uri.parse/1` (docs at
  <https://hexdocs.pm/amqp_client/3.7.7/>) for details on the types of errors
  that can be returned.

      iex> Rbt.Conn.URI.validate("amqp://")
      :ok
      iex> Rbt.Conn.URI.validate("amqp:///test")
      :ok
      iex> Rbt.Conn.URI.validate("amqpp:///test")
      {:error, {:unexpected_uri_scheme, 'amqpp'}}
  """
  @spec validate(t) :: :ok | {:error, term()}
  def validate(uri) do
    case :amqp_uri.parse(uri) do
      {:ok, _} -> :ok
      {:error, {reason, _uri}} -> {:error, reason}
    end
  end

  @doc """
  Allows merging an existing URI string with
  options that needs overriding.

  Specifically:

      iex> uri = "amqp://guest:guest@localhost:15672/my-host?timeout=30"
      iex> Rbt.Conn.URI.merge_options(uri, timeout: 60)
      "amqp://guest:guest@localhost:15672/my-host?timeout=60"

  """
  @spec merge_options(t, Rbt.Conn.open_opts()) :: t
  def merge_options(base_uri, opts) do
    uri = URI.parse(base_uri)
    new_opts = Enum.into(opts, %{}, fn {k, v} -> {to_string(k), v} end)

    final_query =
      case uri.query do
        nil ->
          new_opts

        existing_query_string ->
          existing_opts = URI.decode_query(existing_query_string)
          Map.merge(existing_opts, new_opts)
      end

    uri
    |> Map.put(:query, URI.encode_query(final_query))
    |> URI.to_string()
  end
end
