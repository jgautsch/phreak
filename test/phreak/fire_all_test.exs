defmodule Phreak.FireAllTest do
  use ExUnit.Case

  alias Phreak.Session

  describe "fire_all implementation" do
    test "returns correct format" do
      session = Phreak.new()
      {:ok, updated_session, fired_count} = Phreak.fire_all(session)

      assert %Session{} = updated_session
      assert is_integer(fired_count)
      assert fired_count == 0
    end

    test "processes agenda and counts fired rules" do
      session = Phreak.new()

      # Add a simple rule
      rule = %{
        "name" => "test_rule",
        "conditions" => [
          %{"type" => "test_fact", "constraints" => []}
        ],
        "actions" => ["test_action"]
      }

      {:ok, session} = Phreak.add_rule(session, rule)

      # Assert a matching fact
      session = Phreak.assert(session, %{type: :test_fact, data: "test"})

      # Fire all rules
      {:ok, updated_session, fired_count} = Phreak.fire_all(session)

      assert fired_count == 1
      assert :queue.is_empty(updated_session.agenda)
    end

    test "respects max_fires option" do
      session = Phreak.new()

      # Add a rule that matches all test facts
      rule = %{
        "name" => "count_rule",
        "conditions" => [
          %{"type" => "counter", "constraints" => []}
        ],
        "actions" => ["increment"]
      }

      {:ok, session} = Phreak.add_rule(session, rule)

      # Assert multiple matching facts
      session =
        session
        |> Phreak.assert(%{type: :counter, value: 1})
        |> Phreak.assert(%{type: :counter, value: 2})
        |> Phreak.assert(%{type: :counter, value: 3})
        |> Phreak.assert(%{type: :counter, value: 4})
        |> Phreak.assert(%{type: :counter, value: 5})

      # Fire with limit
      {:ok, updated_session, fired_count} = Phreak.fire_all(session, max_fires: 3)

      assert fired_count == 3
      # Should still have activations in the agenda
      assert not :queue.is_empty(updated_session.agenda)
    end

    test "agenda is properly populated from terminal nodes" do
      session = Phreak.new()

      # Add a rule with specific action
      rule = %{
        "name" => "check_agenda",
        "conditions" => [
          %{
            "type" => "agenda_test",
            "constraints" => [
              %{"field" => "id", "op" => "bind", "var" => "test_id"}
            ]
          }
        ],
        "actions" => ["process_agenda_test"]
      }

      {:ok, session} = Phreak.add_rule(session, rule)

      # Before asserting fact, agenda should be empty
      assert :queue.is_empty(session.agenda)

      # Assert a matching fact
      session = Phreak.assert(session, %{type: :agenda_test, id: 123})

      # After asserting, agenda should have one activation
      assert not :queue.is_empty(session.agenda)

      # Extract the activation to verify its structure
      {{:value, activation}, _} = :queue.out(session.agenda)

      assert activation.rule == "check_agenda"
      assert activation.actions == ["process_agenda_test"]
      assert is_map(activation.bindings)
      assert activation.bindings[:test_id] == 123
    end

    test "fire_all works with empty agenda" do
      session = Phreak.new()

      {:ok, updated_session, fired_count} = Phreak.fire_all(session)

      assert fired_count == 0
      assert updated_session == session
    end

    test "fire_all with infinity max_fires processes all activations" do
      session = Phreak.new()

      # Add a rule
      rule = %{
        "name" => "batch_rule",
        "conditions" => [
          %{"type" => "batch_item", "constraints" => []}
        ],
        "actions" => ["process_batch"]
      }

      {:ok, session} = Phreak.add_rule(session, rule)

      # Assert many facts
      session =
        Enum.reduce(1..10, session, fn i, acc ->
          Phreak.assert(acc, %{type: :batch_item, id: i})
        end)

      # Fire all with default (infinity) max_fires
      {:ok, updated_session, fired_count} = Phreak.fire_all(session)

      assert fired_count == 10
      assert :queue.is_empty(updated_session.agenda)
    end

    test "fire_all with max_fires 0 doesn't fire any rules" do
      session = Phreak.new()

      # Add a rule
      rule = %{
        "name" => "test_rule",
        "conditions" => [
          %{"type" => "test_fact", "constraints" => []}
        ],
        "actions" => ["test_action"]
      }

      {:ok, session} = Phreak.add_rule(session, rule)

      # Assert a matching fact
      session = Phreak.assert(session, %{type: :test_fact})

      # Fire with max_fires 0
      {:ok, updated_session, fired_count} = Phreak.fire_all(session, max_fires: 0)

      assert fired_count == 0
      # Agenda should still have the activation
      assert not :queue.is_empty(updated_session.agenda)
    end
  end
end
