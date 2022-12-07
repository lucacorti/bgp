defmodule BGP do
  @moduledoc """
  Documentation for `BGP`.
  """

  @type asn :: pos_integer()
  @type bgp_id :: IP.Address.t()
  @type hold_time :: non_neg_integer()
end
