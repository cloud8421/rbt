defmodule Rbt.Conn.URI do
  @type t :: String.t()
  @type merge_opts :: %{optional(binary()) => binary()}

  @spec validate(t) :: :ok | {:error, term()}
  def validate(uri) do
    case :amqp_uri.parse(uri) do
      {:ok, _} -> :ok
      {:error, {reason, _uri}} -> {:error, reason}
    end
  end

  @spec merge_options(t, merge_opts) :: t
  def merge_options(base_uri, opts) do
    uri = URI.parse(base_uri)

    final_query =
      case uri.query do
        nil ->
          opts

        existing_query_string ->
          existing_opts = URI.decode_query(existing_query_string)
          Map.merge(existing_opts, opts)
      end

    uri
    |> Map.put(:query, URI.encode_query(final_query))
    |> URI.to_string()
  end
end
