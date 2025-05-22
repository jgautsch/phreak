defmodule Phreak.Nodes.Beta do
  @moduledoc """
  Beta nodes perform joins between facts from different alpha nodes.
  They maintain left and right memories and test join conditions.
  """

  @behaviour Phreak.Node

  defstruct [
    :id,
    :left_parent,
    :right_parent,
    # List of %{left_field: atom, right_field: atom, var: atom}
    :join_tests,
    :successors,
    # List of {fact, bindings} tuples
    :left_memory,
    # List of {fact, bindings} tuples
    :right_memory
  ]

  @impl true
  def left_activate(%__MODULE__{} = node, {fact, bindings}, session) do
    # Store in left memory
    updated_node = %{node | left_memory: [{fact, bindings} | node.left_memory || []]}
    session_with_node = update_node_in_session(session, updated_node)

    # Try to join with all facts in right memory
    joins = find_joins(fact, bindings, updated_node.right_memory || [], node.join_tests, :left)

    # Propagate successful joins
    Enum.reduce(joins, session_with_node, fn {joined_facts, joined_bindings}, acc ->
      propagate_to_successors(updated_node, joined_facts, joined_bindings, acc)
    end)
  end

  @impl true
  def right_activate(%__MODULE__{} = node, {fact, bindings}, session) do
    # Store in right memory
    updated_node = %{node | right_memory: [{fact, bindings} | node.right_memory || []]}
    session_with_node = update_node_in_session(session, updated_node)

    # Try to join with all facts in left memory
    joins = find_joins(fact, bindings, updated_node.left_memory || [], node.join_tests, :right)

    # Propagate successful joins
    Enum.reduce(joins, session_with_node, fn {joined_facts, joined_bindings}, acc ->
      propagate_to_successors(updated_node, joined_facts, joined_bindings, acc)
    end)
  end

  # Find all successful joins between a fact and memory
  defp find_joins(fact, bindings, memory, join_tests, side) do
    Enum.reduce(memory, [], fn {other_fact, other_bindings}, acc ->
      case test_join(fact, bindings, other_fact, other_bindings, join_tests, side) do
        {:ok, joined_bindings} ->
          # Create joined fact tuple based on which side activated
          joined_facts =
            case side do
              :left -> {fact, other_fact}
              :right -> {other_fact, fact}
            end

          [{joined_facts, joined_bindings} | acc]

        :no_match ->
          acc
      end
    end)
  end

  # Test if two facts can join based on join conditions
  defp test_join(left_fact, left_bindings, right_fact, right_bindings, join_tests, _side) do
    # Check all join conditions
    all_match =
      Enum.all?(join_tests, fn test ->
        case test do
          # Variable equality test (most common)
          %{"var" => var} ->
            var_atom = String.to_atom(var)
            Map.get(left_bindings, var_atom) == Map.get(right_bindings, var_atom)

          # Direct field comparison
          %{"left_field" => lf, "right_field" => rf} ->
            left_val = get_field_value(left_fact, lf)
            right_val = get_field_value(right_fact, rf)
            left_val == right_val

          _ ->
            true
        end
      end)

    if all_match do
      # Merge bindings from both sides
      merged = Map.merge(left_bindings, right_bindings)
      {:ok, merged}
    else
      :no_match
    end
  end

  # Extract field value from fact
  defp get_field_value({_type, fields}, field_name) when is_list(fields) do
    field_atom = String.to_existing_atom(field_name)
    Keyword.get(fields, field_atom)
  end

  defp get_field_value(_, _), do: nil

  # Propagate to successor nodes
  defp propagate_to_successors(node, facts, bindings, session) do
    Enum.reduce(node.successors || [], session, fn successor_id, acc ->
      case get_node(acc.network, successor_id) do
        nil -> acc
        successor -> Phreak.Node.left_activate(successor, {facts, bindings}, acc)
      end
    end)
  end

  # Helper to get node from network
  defp get_node(network, node_id) do
    Map.get(network.nodes || %{}, node_id)
  end

  # Update node state in session
  defp update_node_in_session(session, node) do
    updated_network =
      session.network
      |> Map.update(:nodes, %{node.id => node}, fn nodes ->
        Map.put(nodes, node.id, node)
      end)

    %{session | network: updated_network}
  end
end
