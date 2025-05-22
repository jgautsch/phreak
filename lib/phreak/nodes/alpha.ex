defmodule Phreak.Nodes.Alpha do
  @moduledoc """
  Alpha nodes test individual facts against patterns and constraints.
  """

  @behaviour Phreak.Node

  defstruct [:id, :fact_type, :constraints, :successors, :memory]

  @impl true
  def left_activate(%__MODULE__{} = node, fact, session) do
    if matches?(node, fact) do
      # Store in alpha memory
      updated_session = store_in_memory(session, node.id, fact)

      # Extract bindings for propagation
      bindings = extract_bindings(node, fact)

      # Get the updated network with stored nodes
      network = updated_session.network

      # Propagate to successors
      Enum.reduce(node.successors || [], updated_session, fn successor_id, acc ->
        case Map.get(network.nodes || %{}, successor_id) do
          nil ->
            acc

          %Phreak.Nodes.Beta{} = beta ->
            # For beta nodes, determine if this is left or right activation
            if beta.left_parent == node.id do
              Phreak.Node.left_activate(beta, {fact, bindings}, acc)
            else
              Phreak.Node.right_activate(beta, {fact, bindings}, acc)
            end

          successor ->
            Phreak.Node.left_activate(successor, {fact, bindings}, acc)
        end
      end)
    else
      session
    end
  end

  @impl true
  def right_activate(%__MODULE__{}, _fact, session) do
    # Alpha nodes don't receive right activations
    session
  end

  # Check if a fact matches this alpha node's type and constraints
  defp matches?(%__MODULE__{fact_type: expected_type, constraints: constraints}, fact) do
    case fact do
      {actual_type, _args} when is_atom(actual_type) ->
        if actual_type == expected_type do
          # Convert tuple to map for easier field access
          fact_map = tuple_to_map(fact)
          Enum.all?(constraints, &evaluate_constraint(&1, fact_map))
        else
          false
        end

      _ ->
        false
    end
  end

  # Convert fact tuple to map for field access
  defp tuple_to_map({type, args}) when is_list(args) do
    args
    |> Enum.into(%{})
    |> Map.put(:_type, type)
  end

  defp tuple_to_map({type}), do: %{_type: type}

  # Evaluate a single constraint
  defp evaluate_constraint(%{"field" => field, "op" => op} = constraint, fact_map) do
    field_atom = String.to_existing_atom(field)
    field_value = Map.get(fact_map, field_atom)

    case op do
      # Just binding, no test
      "bind" -> true
      "eq" -> field_value == get_constraint_value(constraint, fact_map)
      ">" -> field_value > get_constraint_value(constraint, fact_map)
      "<" -> field_value < get_constraint_value(constraint, fact_map)
      ">=" -> field_value >= get_constraint_value(constraint, fact_map)
      "<=" -> field_value <= get_constraint_value(constraint, fact_map)
      "!=" -> field_value != get_constraint_value(constraint, fact_map)
      _ -> false
    end
  end

  # Get the value to compare against (could be literal or variable reference)
  defp get_constraint_value(%{"value" => value}, _fact_map), do: value
  # For alpha nodes, just check it exists
  defp get_constraint_value(%{"var" => _var}, _fact_map), do: true

  # Extract variable bindings from fact
  defp extract_bindings(%__MODULE__{constraints: constraints}, fact) do
    fact_map = tuple_to_map(fact)

    Enum.reduce(constraints, %{}, fn constraint, acc ->
      case constraint do
        %{"field" => field, "var" => var} ->
          field_atom = String.to_existing_atom(field)
          var_atom = String.to_atom(var)
          Map.put(acc, var_atom, Map.get(fact_map, field_atom))

        _ ->
          acc
      end
    end)
  end

  # Memory management
  defp store_in_memory(session, alpha_id, fact) do
    facts = Map.get(session.wm, alpha_id, [])

    if fact in facts do
      session
    else
      %{session | wm: Map.put(session.wm, alpha_id, [fact | facts])}
    end
  end
end
