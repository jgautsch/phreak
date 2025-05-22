defmodule Phreak.Application do
  @moduledoc false
  use Application

  def start(_type, _args) do
    children = [
      # registry holds named sessions
      {Registry, keys: :unique, name: Phreak.SessionRegistry}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Phreak.Supervisor)
  end
end
