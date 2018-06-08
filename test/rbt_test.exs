defmodule RbtTest do
  use ExUnit.Case
  doctest Rbt

  test "greets the world" do
    assert Rbt.hello() == :world
  end
end
