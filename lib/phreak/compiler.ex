defmodule Phreak.Compiler do
  @moduledoc """
  Compiles JSON rule definitions into Rete network nodes at runtime.
  Supports compound conditions (AND/OR/NOT) and beta joins for variable matching.
  """

  alias Phreak.Session
  alias Phreak.Nodes.{Alpha, Beta, LogicalGate}

  @spec add_rule(Session.t(), map()) :: {:ok, Session.t()} | {:error, term()}
  def add_rule(%Session{network: network} = session, rule_json) do
    with {:ok, rule_name} <- validate_rule_name(rule_json),
         {:ok, condition_ast} <- validate_and_parse_conditions(rule_json),
         {:ok, actions} <- validate_actions(rule_json) do
      # Analyze variables in the rule to determine join requirements
      var_analysis = analyze_variables(condition_ast)

      # Build network nodes from condition AST
      {root_node, next_id, updated_network} =
        build_network_from_ast(
          condition_ast,
          Map.get(network, :next_node_id, 0),
          network,
          var_analysis
        )

      # Create terminal node for actions
      terminal_id = :"terminal_#{rule_name}"

      terminal = %{
        id: terminal_id,
        rule_name: rule_name,
        actions: actions
      }

      # Connect root to terminal
      root_with_terminal = add_successor(root_node, terminal_id)

      # Update network
      updated_network =
        updated_network
        |> Map.put(:next_node_id, next_id)
        |> store_network_nodes(root_with_terminal, terminal)
        |> Map.update(:rules, [{rule_name, rule_json}], &(&1 ++ [{rule_name, rule_json}]))

      {:ok, %{session | network: updated_network}}
    end
  end

  # Analyze variables across the entire rule
  defp analyze_variables(ast) do
    vars = collect_variables(ast, %{})

    # Group by variable name to find which facts share variables
    Enum.reduce(vars, %{}, fn {var, fact_info}, acc ->
      Map.update(acc, var, [fact_info], &(&1 ++ [fact_info]))
    end)
  end

  defp collect_variables({:and, children}, acc) do
    Enum.reduce(children, acc, &collect_variables/2)
  end

  defp collect_variables({:or, children}, acc) do
    Enum.reduce(children, acc, &collect_variables/2)
  end

  defp collect_variables({:not, child}, acc) do
    collect_variables(child, acc)
  end

  defp collect_variables({:fact, %{"type" => type, "constraints" => constraints}}, acc) do
    Enum.reduce(constraints, acc, fn
      %{"var" => var, "field" => field}, acc ->
        Map.put(acc, {String.to_atom(var), String.to_atom(type)}, %{
          type: String.to_atom(type),
          field: String.to_atom(field)
        })

      _, acc ->
        acc
    end)
  end

  # Validation functions
  defp validate_rule_name(%{"name" => name}) when is_binary(name), do: {:ok, name}
  defp validate_rule_name(_), do: {:error, "Rule must have a 'name' field"}

  defp validate_and_parse_conditions(%{"conditions" => conditions}) do
    {:ok, parse_condition_ast(conditions)}
  end

  defp validate_and_parse_conditions(_), do: {:error, "Rule must have 'conditions'"}

  defp validate_actions(%{"actions" => actions}) when is_list(actions), do: {:ok, actions}
  defp validate_actions(_), do: {:error, "Rule must have 'actions' array"}

  # Parse conditions into AST
  defp parse_condition_ast(conditions) when is_list(conditions) do
    # List of conditions = implicit AND
    {:and, Enum.map(conditions, &parse_condition_ast/1)}
  end

  defp parse_condition_ast(%{"and" => conditions}) when is_list(conditions) do
    {:and, Enum.map(conditions, &parse_condition_ast/1)}
  end

  defp parse_condition_ast(%{"or" => conditions}) when is_list(conditions) do
    {:or, Enum.map(conditions, &parse_condition_ast/1)}
  end

  defp parse_condition_ast(%{"not" => condition}) do
    {:not, parse_condition_ast(condition)}
  end

  defp parse_condition_ast(%{"type" => _type, "constraints" => _constraints} = fact_pattern) do
    {:fact, fact_pattern}
  end

  # Build network from AST
  defp build_network_from_ast({:and, children}, id, network, var_analysis) do
    # For AND nodes, we need to check if children share variables
    # If they do, we need beta joins
    case children do
      [{:fact, _}, {:fact, _} | _] = facts ->
        # Multiple facts in AND - check for shared variables
        {node, next_id, updated_network} = build_beta_network(facts, id, network, var_analysis)
        {node, next_id, updated_network}

      _ ->
        # Mixed nodes or no direct fact children - use gate
        build_gate_network(:and, children, id, network, var_analysis)
    end
  end

  defp build_network_from_ast({:or, children}, id, network, var_analysis) do
    build_gate_network(:or, children, id, network, var_analysis)
  end

  defp build_network_from_ast({:not, child_ast}, id, network, var_analysis) do
    # Create NOT gate node
    gate_node = %LogicalGate{
      id: :"gate_not_#{id}",
      gate_type: :not,
      expected_count: 0,
      successors: []
    }

    # Build child node and carry updated network through
    {child_node, next_id, updated_network} =
      build_network_from_ast(child_ast, id + 1, network, var_analysis)

    # Connect child to gate and store the updated child in the network
    connected_child = add_successor(child_node, gate_node.id)
    updated_network = put_node(updated_network, connected_child)

    {%{gate_node | successors: [connected_child.id]}, next_id, updated_network}
  end

  defp build_network_from_ast({:fact, fact_pattern}, id, network, _var_analysis) do
    alpha_node = build_alpha_from_json(fact_pattern, id)
    {alpha_node, id + 1, network}
  end

  # Build beta network for facts with shared variables
  defp build_beta_network(fact_asts, start_id, network, var_analysis) do
    # First, create alpha nodes for each fact
    {alpha_nodes, next_id} =
      Enum.reduce(fact_asts, {[], start_id}, fn {:fact, pattern}, {nodes, id} ->
        alpha = build_alpha_from_json(pattern, id)
        {nodes ++ [alpha], id + 1}
      end)

    # Now create beta nodes to join them
    case alpha_nodes do
      [first | rest] when rest != [] ->
        # Chain beta nodes: first + second -> beta1, beta1 + third -> beta2, etc.
        {final_beta, final_id, updated_network} =
          create_beta_chain(first, rest, next_id, var_analysis, network)

        {final_beta, final_id, updated_network}

      [single] ->
        # Only one fact, no join needed
        {single, next_id, network}

      [] ->
        # No facts?
        {%LogicalGate{id: :"empty_#{start_id}", gate_type: :and, successors: []}, start_id + 1,
         network}
    end
  end

  # Create a chain of beta nodes, threading the network through
  defp create_beta_chain(left_node, [right_node | rest], id, var_analysis, network) do
    # Determine join conditions between left and right
    join_tests = find_join_tests(left_node, right_node, var_analysis)

    # Create beta node
    beta = %Beta{
      id: :"beta_#{id}",
      left_parent: get_node_id(left_node),
      right_parent: get_node_id(right_node),
      join_tests: join_tests,
      successors: [],
      left_memory: [],
      right_memory: []
    }

    # Connect nodes to beta
    updated_left = add_successor(left_node, beta.id)
    updated_right = add_successor(right_node, beta.id)

    # Store updated nodes in the network
    network =
      network
      |> Map.update(
        :nodes,
        %{updated_left.id => updated_left, updated_right.id => updated_right},
        fn nodes ->
          nodes
          |> Map.put(updated_left.id, updated_left)
          |> Map.put(updated_right.id, updated_right)
        end
      )

    if rest == [] do
      # This is the final beta
      {beta, id + 1, network}
    else
      # Continue chaining with beta as the new left
      create_beta_chain(beta, rest, id + 1, var_analysis, network)
    end
  end

  # Get node ID (handles both alpha nodes and beta nodes)
  defp get_node_id(%{id: id}), do: id

  # Find variables that should be joined between two nodes
  defp find_join_tests(
         %Alpha{constraints: left_constraints},
         %Alpha{constraints: right_constraints},
         _var_analysis
       ) do
    # Find variables that appear in both constraint sets
    left_vars = extract_vars_from_constraints(left_constraints)
    right_vars = extract_vars_from_constraints(right_constraints)

    # Intersection of variables
    MapSet.intersection(left_vars, right_vars)
    |> MapSet.to_list()
    |> Enum.map(fn var -> %{"var" => to_string(var)} end)
  end

  defp find_join_tests(%Beta{} = _left_beta, %Alpha{} = _right_alpha, _var_analysis) do
    # For beta-to-alpha joins, we need to consider all variables from the beta's history
    # This is simplified for now - full implementation would track all variables through the beta chain
    []
  end

  defp find_join_tests(_, _, _), do: []

  defp extract_vars_from_constraints(constraints) do
    constraints
    |> Enum.reduce(MapSet.new(), fn
      %{"var" => var}, acc -> MapSet.put(acc, String.to_atom(var))
      _, acc -> acc
    end)
  end

  # Build gate network (for OR, complex AND)
  defp build_gate_network(gate_type, children, id, network, var_analysis) do
    # Create gate node
    gate_node = %LogicalGate{
      id: :"gate_#{gate_type}_#{id}",
      gate_type: gate_type,
      expected_count:
        case gate_type do
          :and -> length(children)
          :or -> 1
        end,
      successors: []
    }

    # Build child nodes and propagate network updates
    {child_nodes, next_id, network_after_children} =
      Enum.reduce(children, {[], id + 1, network}, fn child_ast, {nodes, cur_id, net_acc} ->
        {node, next_id_child, new_net} =
          build_network_from_ast(child_ast, cur_id, net_acc, var_analysis)

        {nodes ++ [node], next_id_child, new_net}
      end)

    # Connect children to gate and store updated nodes
    {connected_children, final_network} =
      Enum.map_reduce(child_nodes, network_after_children, fn child, net ->
        updated_child = add_successor(child, gate_node.id)
        {updated_child, put_node(net, updated_child)}
      end)

    # Store child IDs in gate
    gate_with_children = %{gate_node | successors: Enum.map(connected_children, & &1.id)}

    {gate_with_children, next_id, final_network}
  end

  # Helper functions
  defp add_successor(node, successor_id) do
    %{node | successors: (node.successors || []) ++ [successor_id]}
  end

  defp put_node(network, node) do
    Map.update(network, :nodes, %{node.id => node}, fn nodes ->
      Map.put(nodes, node.id, node)
    end)
  end

  # Helper to store all nodes in the network
  defp store_network_nodes(network, root_node, terminal) do
    # Collect all nodes from the tree
    all_nodes = collect_nodes_recursive(root_node, %{})

    # Add terminal
    all_nodes = Map.put(all_nodes, terminal.id, terminal)

    # Update network with all nodes
    Map.put(network, :nodes, Map.merge(Map.get(network, :nodes, %{}), all_nodes))
  end

  # Recursively collect all nodes in the network
  defp collect_nodes_recursive(node, acc) do
    acc = Map.put(acc, node.id, node)

    # For each successor ID, we don't recurse because nodes are already collected
    # during the build process
    acc
  end

  defp build_alpha_from_json(%{"type" => type, "constraints" => constraints}, id) do
    %Alpha{
      id: :"alpha_#{id}",
      fact_type: String.to_atom(type),
      constraints: constraints,
      successors: [],
      memory: []
    }
  end
end
