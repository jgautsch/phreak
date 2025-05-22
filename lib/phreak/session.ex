defmodule Phreak.Session do
  @moduledoc """
  A `Session` owns a network and working‑memory.
  Sessions can be created empty and have rules added at runtime.
  """

  alias __MODULE__
  alias Phreak.Engine

  @type t :: %Session{
          network: map(),
          # :alpha_id ⇒ tuple list / etc.
          wm: map(),
          agenda: :queue.queue(),
          opts: keyword()
        }
  defstruct network: %{
              rules: [],
              alpha_roots: [],
              terminal_nodes: [],
              segments: [],
              next_node_id: 0,
              nodes: %{}
            },
            wm: %{},
            agenda: :queue.new(),
            opts: []

  # Public API -------------------------------------------------------------

  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %Session{opts: opts}
  end

  @spec assert(t(), term()) :: t()
  def assert(%Session{} = s, fact) do
    Engine.assert(s, fact)
  end

  @spec retract(t(), term()) :: t()
  def retract(%Session{} = s, fact) do
    Engine.retract(s, fact)
  end

  @spec fire_all(t(), keyword()) :: t()
  def fire_all(%Session{} = s, opts \\ []) do
    Engine.fire_all(s, opts)
  end
end
