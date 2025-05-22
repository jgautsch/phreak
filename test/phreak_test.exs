defmodule PhreakTest do
  use ExUnit.Case

  describe "compiler builds network for basic conditions" do
    test "simple fact condition" do
      session = Phreak.new()

      rule = %{
        "name" => "simple_rule",
        "conditions" => [
          %{
            "type" => "patient",
            "constraints" => [%{"field" => "age", "op" => ">", "value" => 18}]
          }
        ],
        "actions" => []
      }

      {:ok, session} = Phreak.add_rule(session, rule)

      # Should have at least: alpha node + terminal node
      assert map_size(session.network.nodes) >= 2

      # Check that the rule was stored
      assert length(session.network.rules) == 1
      assert {"simple_rule", ^rule} = hd(session.network.rules)
    end

    test "OR conditions" do
      session = Phreak.new()

      rule = %{
        "name" => "or_rule",
        "conditions" => %{
          "or" => [
            %{
              "type" => "patient",
              "constraints" => [%{"field" => "id", "op" => "bind", "var" => "id"}]
            },
            %{
              "type" => "lab",
              "constraints" => [%{"field" => "patient_id", "op" => "bind", "var" => "id"}]
            }
          ]
        },
        "actions" => []
      }

      {:ok, session} = Phreak.add_rule(session, rule)

      # Should have: 2 alpha nodes + 1 OR gate + terminal
      assert map_size(session.network.nodes) >= 4

      # Verify OR gate exists
      or_gates =
        session.network.nodes
        |> Map.values()
        |> Enum.filter(fn
          %{gate_type: :or} -> true
          _ -> false
        end)

      assert length(or_gates) == 1
    end

    test "AND conditions with shared variables (beta join)" do
      session = Phreak.new()

      rule = %{
        "name" => "join_rule",
        "conditions" => [
          %{
            "type" => "patient",
            "constraints" => [%{"field" => "id", "op" => "bind", "var" => "pid"}]
          },
          %{
            "type" => "lab_result",
            "constraints" => [
              %{"field" => "patient_id", "op" => "bind", "var" => "pid"},
              %{"field" => "value", "op" => ">", "value" => 100}
            ]
          }
        ],
        "actions" => []
      }

      {:ok, session} = Phreak.add_rule(session, rule)

      # Should have: 2 alpha nodes + 1 beta node + terminal
      assert map_size(session.network.nodes) >= 4

      # Verify beta node exists
      beta_nodes =
        session.network.nodes
        |> Map.values()
        |> Enum.filter(fn
          %{left_parent: _, right_parent: _} -> true
          _ -> false
        end)

      assert length(beta_nodes) == 1
    end

    test "NOT conditions" do
      session = Phreak.new()

      rule = %{
        "name" => "not_rule",
        "conditions" => %{
          "not" => %{
            "type" => "prescription",
            "constraints" => [%{"field" => "drug", "op" => "=", "value" => "aspirin"}]
          }
        },
        "actions" => []
      }

      {:ok, session} = Phreak.add_rule(session, rule)

      # Should have: 1 alpha node + 1 NOT gate + terminal
      assert map_size(session.network.nodes) >= 3

      # Verify NOT gate exists
      not_gates =
        session.network.nodes
        |> Map.values()
        |> Enum.filter(fn
          %{gate_type: :not} -> true
          _ -> false
        end)

      assert length(not_gates) == 1
    end
  end

  describe "complex rule conditions" do
    test "nested AND/OR conditions" do
      session = Phreak.new()

      rule = %{
        "name" => "complex_rule",
        "conditions" => %{
          "and" => [
            %{
              "type" => "patient",
              "constraints" => [%{"field" => "age", "op" => ">", "value" => 65}]
            },
            %{
              "or" => [
                %{
                  "type" => "diagnosis",
                  "constraints" => [%{"field" => "code", "op" => "=", "value" => "diabetes"}]
                },
                %{
                  "type" => "diagnosis",
                  "constraints" => [%{"field" => "code", "op" => "=", "value" => "hypertension"}]
                }
              ]
            }
          ]
        },
        "actions" => []
      }

      {:ok, session} = Phreak.add_rule(session, rule)

      # Should have multiple nodes for nested structure
      assert map_size(session.network.nodes) >= 5

      # Should have both AND and OR gates
      gates =
        session.network.nodes
        |> Map.values()
        |> Enum.filter(fn
          %{gate_type: _} -> true
          _ -> false
        end)

      assert length(gates) >= 2
    end

    test "multiple facts with multiple shared variables" do
      session = Phreak.new()

      rule = %{
        "name" => "multi_join_rule",
        "conditions" => [
          %{
            "type" => "patient",
            "constraints" => [
              %{"field" => "id", "op" => "bind", "var" => "pid"},
              %{"field" => "physician_id", "op" => "bind", "var" => "doc"}
            ]
          },
          %{
            "type" => "appointment",
            "constraints" => [
              %{"field" => "patient_id", "op" => "bind", "var" => "pid"},
              %{"field" => "doctor_id", "op" => "bind", "var" => "doc"},
              %{"field" => "date", "op" => "bind", "var" => "apt_date"}
            ]
          },
          %{
            "type" => "prescription",
            "constraints" => [
              %{"field" => "patient_id", "op" => "bind", "var" => "pid"},
              %{"field" => "prescriber_id", "op" => "bind", "var" => "doc"}
            ]
          }
        ],
        "actions" => []
      }

      {:ok, session} = Phreak.add_rule(session, rule)

      # Should create beta chain for joining 3 facts
      beta_nodes =
        session.network.nodes
        |> Map.values()
        |> Enum.filter(fn
          %{left_parent: _, right_parent: _} -> true
          _ -> false
        end)

      # Should have 2 beta nodes (fact1+fact2 -> beta1, beta1+fact3 -> beta2)
      assert length(beta_nodes) == 2
    end

    test "combination of NOT within OR" do
      session = Phreak.new()

      rule = %{
        "name" => "not_in_or_rule",
        "conditions" => %{
          "or" => [
            %{
              "type" => "patient",
              "constraints" => [%{"field" => "vip", "op" => "=", "value" => true}]
            },
            %{
              "not" => %{
                "type" => "insurance",
                "constraints" => [%{"field" => "expired", "op" => "=", "value" => true}]
              }
            }
          ]
        },
        "actions" => []
      }

      {:ok, session} = Phreak.add_rule(session, rule)

      # Should have both OR and NOT gates
      gates =
        session.network.nodes
        |> Map.values()
        |> Enum.reduce(%{or: 0, not: 0}, fn
          %{gate_type: :or}, acc -> %{acc | or: acc.or + 1}
          %{gate_type: :not}, acc -> %{acc | not: acc.not + 1}
          _, acc -> acc
        end)

      assert gates.or == 1
      assert gates.not == 1
    end
  end

  describe "multiple rules" do
    test "adding multiple rules to same session" do
      session = Phreak.new()

      rules = [
        %{
          "name" => "rule1",
          "conditions" => [%{"type" => "patient", "constraints" => []}],
          "actions" => []
        },
        %{
          "name" => "rule2",
          "conditions" => [%{"type" => "doctor", "constraints" => []}],
          "actions" => []
        }
      ]

      {:ok, session} = Phreak.add_rules(session, rules)

      assert length(session.network.rules) == 2

      # Each rule should have its own terminal
      terminals =
        session.network.nodes
        |> Map.values()
        |> Enum.filter(fn
          %{rule_name: _} -> true
          _ -> false
        end)

      assert length(terminals) == 2
    end

    test "rules can share alpha nodes" do
      session = Phreak.new()

      # Two rules with same fact type and constraints
      rule1 = %{
        "name" => "high_temp_rule",
        "conditions" => [
          %{
            "type" => "patient",
            "constraints" => [%{"field" => "temp", "op" => ">", "value" => 38}]
          }
        ],
        "actions" => ["alert_nurse"]
      }

      rule2 = %{
        "name" => "critical_temp_rule",
        "conditions" => [
          %{
            "type" => "patient",
            "constraints" => [%{"field" => "temp", "op" => ">", "value" => 38}]
          },
          %{
            "type" => "patient",
            "constraints" => [%{"field" => "temp", "op" => ">", "value" => 40}]
          }
        ],
        "actions" => ["alert_doctor"]
      }

      {:ok, session1} = Phreak.add_rule(session, rule1)
      {:ok, session2} = Phreak.add_rule(session1, rule2)
      session = session2

      # Should have 2 rules but potentially shared nodes
      assert length(session.network.rules) == 2
    end
  end

  describe "validation and error handling" do
    test "rule without name is rejected" do
      session = Phreak.new()

      rule = %{
        "conditions" => [%{"type" => "patient", "constraints" => []}],
        "actions" => []
      }

      assert {:error, "Rule must have a 'name' field"} = Phreak.add_rule(session, rule)
    end

    test "rule without conditions is rejected" do
      session = Phreak.new()

      rule = %{
        "name" => "invalid_rule",
        "actions" => []
      }

      assert {:error, "Rule must have 'conditions'"} = Phreak.add_rule(session, rule)
    end

    test "rule without actions is rejected" do
      session = Phreak.new()

      rule = %{
        "name" => "invalid_rule",
        "conditions" => [%{"type" => "patient", "constraints" => []}]
      }

      assert {:error, "Rule must have 'actions' array"} = Phreak.add_rule(session, rule)
    end

    test "actions must be a list" do
      session = Phreak.new()

      rule = %{
        "name" => "invalid_rule",
        "conditions" => [%{"type" => "patient", "constraints" => []}],
        "actions" => "not_a_list"
      }

      assert {:error, "Rule must have 'actions' array"} = Phreak.add_rule(session, rule)
    end
  end

  describe "constraint types" do
    test "various constraint operators" do
      session = Phreak.new()

      rule = %{
        "name" => "constraint_test",
        "conditions" => [
          %{
            "type" => "patient",
            "constraints" => [
              %{"field" => "age", "op" => ">", "value" => 18},
              %{"field" => "name", "op" => "=", "value" => "John"},
              %{"field" => "id", "op" => "bind", "var" => "patient_id"},
              %{"field" => "temp", "op" => ">=", "value" => 37.5},
              %{"field" => "active", "op" => "!=", "value" => false}
            ]
          }
        ],
        "actions" => []
      }

      {:ok, session} = Phreak.add_rule(session, rule)
      assert map_size(session.network.nodes) >= 2
    end
  end

  describe "JSON loading" do
    test "load rules from JSON string" do
      session = Phreak.new()

      json = """
      [
        {
          "name": "json_rule_1",
          "conditions": [
            {"type": "patient", "constraints": [{"field": "age", "op": ">", "value": 65}]}
          ],
          "actions": ["send_reminder"]
        },
        {
          "name": "json_rule_2",
          "conditions": {
            "or": [
              {"type": "lab", "constraints": []},
              {"type": "xray", "constraints": []}
            ]
          },
          "actions": []
        }
      ]
      """

      {:ok, session} = Phreak.load_rules_json(session, json)
      assert length(session.network.rules) == 2
    end

    test "invalid JSON returns error" do
      session = Phreak.new()

      assert {:error, _} = Phreak.load_rules_json(session, "not valid json")
    end
  end
end
