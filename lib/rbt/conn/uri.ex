defmodule Rbt.Conn.URI do
  @type t :: String.t()

  @spec validate(t) :: :ok | {:error, term()}
  def validate(uri) do
    case :amqp_uri.parse(uri) do
      {:ok, _} -> :ok
      {:error, {reason, _uri}} -> {:error, reason}
    end
  end

  @spec merge_options(t, Enum.t()) :: t
  def merge_options(base_uri, options) do
    uri = URI.parse(base_uri)

    final_query =
      case uri.query do
        nil ->
          options

        options ->
          URI.decode_query(options, options)
      end

    uri
    |> Map.put(:query, URI.encode_query(final_query))
    |> URI.to_string()
  end
end
