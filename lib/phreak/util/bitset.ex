defmodule Phreak.Util.BitSet do
  @moduledoc false
  @type t :: non_neg_integer()

  import Bitwise

  def new, do: 0
  def set(bitset, pos), do: bitset ||| 1 <<< pos
  def unset(bitset, pos), do: bitset &&& bnot(1 <<< pos)
  def on?(bitset, pos), do: (bitset &&& 1 <<< pos) != 0
  def all_on?(bitset, mask), do: (bitset &&& mask) == mask
end
