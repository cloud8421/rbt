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
    # TODO define a proper recursive json generator
    let v <-
          list(
            {utf8(),
             oneof([
               list(json_value()),
               json_value()
             ])}
          ) do
      Enum.into(v, %{})
    end
  end

  def json_value do
    oneof([utf8(), integer(), float()])
  end
end
