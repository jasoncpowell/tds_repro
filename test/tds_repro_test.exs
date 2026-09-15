defmodule TdsReproTest do
  use ExUnit.Case
  doctest TdsRepro

  test "greets the world" do
    assert TdsRepro.hello() == :world
  end
end
