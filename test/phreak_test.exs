defmodule PhreakTest do
  use ExUnit.Case
  doctest Phreak

  test "greets the world" do
    assert Phreak.hello() == :world
  end
end
