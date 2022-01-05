defmodule BGP do
  @moduledoc """
  Documentation for `BGP`.
  """
  alias BGP.Prefix

  @type asn :: pos_integer()
  @type bgp_id :: Prefix.t()
  @type hold_time :: non_neg_integer()
end
