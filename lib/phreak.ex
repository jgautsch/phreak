defmodule Phreak do
  @moduledoc """
  Phreak Rules Engine - Runtime rule creation from JSON
  """

  alias Phreak.{Session, Compiler}

  # Create a new session with empty network
  defdelegate new(opts \\ []), to: Session, as: :new

  # Add rules to a session from JSON
  @spec add_rule(Session.t(), map()) :: {:ok, Session.t()} | {:error, term()}
  def add_rule(session, rule_json) when is_map(rule_json) do
    Compiler.add_rule(session, rule_json)
  end

  # Add multiple rules
  @spec add_rules(Session.t(), [map()]) :: {:ok, Session.t()} | {:error, term()}
  def add_rules(session, rules_json) when is_list(rules_json) do
    Enum.reduce_while(rules_json, {:ok, session}, fn rule, {:ok, sess} ->
      case add_rule(sess, rule) do
        {:ok, new_sess} -> {:cont, {:ok, new_sess}}
        error -> {:halt, error}
      end
    end)
  end

  # Load rules from JSON string
  @spec load_rules_json(Session.t(), String.t()) :: {:ok, Session.t()} | {:error, term()}
  def load_rules_json(session, json_string) when is_binary(json_string) do
    case Jason.decode(json_string) do
      {:ok, rules} -> add_rules(session, rules)
      {:error, _} = error -> error
    end
  end

  defdelegate assert(session, fact), to: Session
  defdelegate retract(session, fact), to: Session
  defdelegate fire_all(session, opts \\ []), to: Session
end
