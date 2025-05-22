defmodule Phreak.Node do
  @moduledoc """
  Behaviour for all Rete network nodes and dispatcher functions.
  """

  @callback left_activate(node :: struct(), tuple :: term(), session :: Phreak.Session.t()) ::
              Phreak.Session.t()
  @callback right_activate(node :: struct(), tuple :: term(), session :: Phreak.Session.t()) ::
              Phreak.Session.t()

  # Dispatcher functions that call the appropriate module based on node type
  def left_activate(node, fact, session)

  # Handle struct nodes (Alpha, Beta, LogicalGate)
  def left_activate(%module{} = node, fact, session) do
    module.left_activate(node, fact, session)
  end

  # Handle terminal nodes (plain maps with id, rule_name, actions)
  def left_activate(
        %{id: id, rule_name: rule_name, actions: actions} = _terminal,
        {facts, bindings},
        session
      ) do
    # Queue activation for firing
    activation = %{
      rule: rule_name,
      facts: facts,
      bindings: bindings,
      actions: actions
    }

    updated_agenda = :queue.in(activation, session.agenda)
    %{session | agenda: updated_agenda}
  end

  # Fallback for other node types
  def left_activate(_node, _fact, session), do: session

  def right_activate(node, fact, session)

  # Handle struct nodes
  def right_activate(%module{} = node, fact, session) do
    module.right_activate(node, fact, session)
  end

  # Terminal nodes don't handle right activation
  def right_activate(%{id: _id, rule_name: _rule_name, actions: _actions}, _fact, session) do
    session
  end

  # Fallback
  def right_activate(_node, _fact, session), do: session
end
