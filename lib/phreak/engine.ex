defmodule Phreak.Engine do
  @moduledoc """
  The heart of Phreak.  Implements:
  * set‑oriented `assert` → propagates to alpha memories
  * dynamic linking using bit‑masks (segment on/off)
  * agenda queue / salience ordering
  * fire loop
  """

  alias Phreak.Session

  @spec assert(Session.t(), term()) :: Session.t()
  def assert(%Session{network: net} = session, fact) do
    # Normalize fact format - convert map to tuple if needed
    normalized_fact = normalize_fact(fact)

    # Store the original fact in a general working memory location
    session = store_fact_in_wm(session, fact)

    # For the new structure, we need to find all alpha nodes in the network
    # that match the fact type and activate them
    nodes = Map.get(net, :nodes, %{})

    fact_type =
      case normalized_fact do
        {type, _} -> type
        _ -> nil
      end

    # Find and activate all matching alpha nodes
    Enum.reduce(nodes, session, fn {_id, node}, acc_session ->
      case node do
        %Phreak.Nodes.Alpha{fact_type: ^fact_type} ->
          Phreak.Node.left_activate(node, normalized_fact, acc_session)

        _ ->
          acc_session
      end
    end)
  end

  @spec retract(Session.t(), term()) :: Session.t()
  def retract(%Session{} = session, fact) do
    # Remove from general working memory
    session = remove_fact_from_wm(session, fact)

    # TODO: implement retraction from alpha memories and propagate retractions
    session
  end

  @spec fire_all(Session.t(), keyword()) :: {:ok, Session.t(), non_neg_integer()}
  def fire_all(%Session{} = session, opts \\ []) do
    max_fires = Keyword.get(opts, :max_fires, :infinity)
    fire_loop(session, 0, max_fires)
  end

  # Private functions

  defp fire_loop(%Session{} = session, fired_count, max_fires)
       when fired_count >= max_fires do
    {:ok, session, fired_count}
  end

  defp fire_loop(%Session{agenda: agenda} = session, fired_count, max_fires) do
    case :queue.out(agenda) do
      {{:value, activation}, new_agenda} ->
        # Execute the activation
        new_session = execute_activation(%{session | agenda: new_agenda}, activation)

        # Continue firing
        fire_loop(new_session, fired_count + 1, max_fires)

      {:empty, _} ->
        # No more activations
        {:ok, session, fired_count}
    end
  end

  defp execute_activation(session, %{
         rule: rule,
         facts: _facts,
         bindings: _bindings,
         actions: actions
       }) do
    # For now, just log the execution
    IO.inspect({:executing_rule, rule, actions}, label: "[Phreak] fire")

    # In a real implementation, this would call the action handlers
    # with the facts and bindings
    session
  end

  defp normalize_fact(fact) when is_map(fact) do
    # Convert map-style fact to tuple format
    type = Map.get(fact, :type)

    if type do
      # Remove :type from the map and convert to keyword list
      attrs = Map.delete(fact, :type)
      {type, Enum.to_list(attrs)}
    else
      fact
    end
  end

  defp normalize_fact(fact), do: fact

  defp store_fact_in_wm(session, fact) do
    # Store facts in a general :facts key in working memory
    facts = Map.get(session.wm, :facts, [])

    if fact in facts do
      session
    else
      %{session | wm: Map.put(session.wm, :facts, [fact | facts])}
    end
  end

  defp remove_fact_from_wm(session, fact) do
    facts = Map.get(session.wm, :facts, [])
    new_facts = List.delete(facts, fact)

    if new_facts == [] do
      %{session | wm: Map.delete(session.wm, :facts)}
    else
      %{session | wm: Map.put(session.wm, :facts, new_facts)}
    end
  end
end
