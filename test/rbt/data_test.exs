defmodule Rbt.DataTest do
  use ExUnit.Case
  use PropCheck

  alias Rbt.Data

  property "native encode/decode" do
    forall payload <- any() do
      {:ok, encoded} = Data.encode(payload, "application/octet-stream")
      assert {:ok, payload} == Data.decode(encoded, "application/octet-stream")
    end
  end

  property "json encode/decode" do
    forall payload <- json() do
      {:ok, encoded} = Data.encode(payload, "application/json")
      assert {:ok, payload} == Data.decode(encoded, "application/json")
    end
  end

  def json do
    # TODO: figure out recursive json
    # let j <- vector(5, {utf8(), oneof([json_value(), lazy(json())])}) do
    let j <- vector(5, {utf8(), json_value()}) do
      Enum.into(j, %{})
    end
  end

  def json_value do
    oneof([scalar_value(), list(scalar_value())])
  end

  def scalar_value do
    oneof([utf8(), integer(), float(), boolean(), nil])
  end
end
