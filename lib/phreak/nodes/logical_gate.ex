defmodule Phreak.Nodes.LogicalGate do
  @moduledoc """
  Logical gate nodes implement AND/OR/NOT operations in the Rete network.
  They collect activations from multiple children and fire based on logic type.
  """

  @behaviour Phreak.Node

  defstruct [:id, :gate_type, :expected_count, :successors, :activations]

  @impl true
  def left_activate(%__MODULE__{} = node, {fact, bindings}, session) do
    # Track activation from child by updating activations map
    updated_activations = Map.put(node.activations || %{}, fact, bindings)
    updated_node = %{node | activations: updated_activations}

    # Store updated node state first
    session_with_node = update_node_in_session(session, updated_node)

    # Check if gate should fire
    if should_fire?(updated_node) do
      # Merge all bindings
      merged_bindings = merge_bindings(updated_node.activations)

      # Propagate to successors
      Enum.reduce(updated_node.successors || [], session_with_node, fn successor_id, acc ->
        case get_node(acc.network, successor_id) do
          nil -> acc
          successor -> Phreak.Node.left_activate(successor, {fact, merged_bindings}, acc)
        end
      end)
    else
      session_with_node
    end
  end

  @impl true
  def right_activate(%__MODULE__{}, _fact, session) do
    # TODO: Handle retractions
    session
  end

  # Determine if gate should fire based on type and activations
  defp should_fire?(%__MODULE__{gate_type: :and, expected_count: expected, activations: acts}) do
    map_size(acts || %{}) >= expected
  end

  defp should_fire?(%__MODULE__{gate_type: :or, activations: acts}) do
    map_size(acts || %{}) >= 1
  end

  defp should_fire?(%__MODULE__{gate_type: :not, expected_count: 0, activations: acts}) do
    # NOT gate fires when NO children have activated
    map_size(acts || %{}) == 0
  end

  # Merge bindings from all activations
  defp merge_bindings(activations) do
    activations
    |> Map.values()
    |> Enum.reduce(%{}, &Map.merge(&2, &1))
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
