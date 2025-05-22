defmodule PhreakTest do
  use ExUnit.Case

  test "compiler builds network for OR conditions" do
    session = Phreak.new()

    rule = %{
      "name" => "or_rule",
      "conditions" => %{
        "or" => [
          %{"type" => "patient", "constraints" => [%{"field" => "id", "op" => "bind", "var" => "id"}]},
          %{"type" => "lab", "constraints" => [%{"field" => "patient_id", "op" => "bind", "var" => "id"}]}
        ]
      },
      "actions" => []
    }

    {:ok, session} = Phreak.add_rule(session, rule)
    assert map_size(session.network.nodes) >= 4
  end
end
