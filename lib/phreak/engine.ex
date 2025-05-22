defmodule Phreak.Engine do
  @moduledoc """
  The heart of Phreak.  Implements:
  * set‑oriented `assert` → propagates to alpha memories
  * dynamic linking using bit‑masks (segment on/off)
  * agenda queue / salience ordering
  * fire loop
  """

  alias Phreak.{Util.BitSet, Node, Session}

  @spec assert(Session.t(), term()) :: Session.t()
  def assert(%Session{network: net} = session, fact) do
    # For the new structure, we need to find all alpha nodes in the network
    # that match the fact type and activate them
    nodes = Map.get(net, :nodes, %{})

    fact_type =
      case fact do
        {type, _} -> type
        _ -> nil
      end

    # Find and activate all matching alpha nodes
    Enum.reduce(nodes, session, fn {_id, node}, acc_session ->
      case node do
        %Phreak.Nodes.Alpha{fact_type: ^fact_type} ->
          Phreak.Node.left_activate(node, fact, acc_session)

        _ ->
          acc_session
      end
    end)
  end

  @spec retract(Session.t(), term()) :: Session.t()
  def retract(%Session{} = s, fact) do
    IO.inspect({:retract, fact}, label: "[Phreak] retract")
    # TODO: implement retraction
    s
  end

  @spec fire_all(Session.t(), keyword()) :: Session.t()
  def fire_all(%Session{} = s, _opts) do
    # TODO: implement agenda processing
    IO.inspect(:fire_all, label: "[Phreak] firing")
    s
  end
end
