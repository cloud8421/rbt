defmodule RbtTest do
  use ExUnit.Case
  use PropCheck

  doctest Rbt

  test "greets the world" do
    assert Rbt.hello() == :world
  end

  property "always works" do
    forall type <- term() do
      boolean(type)
    end
  end

  def boolean(_) do
    true
  end
end
