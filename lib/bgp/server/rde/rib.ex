defmodule BGP.Server.RDE.RIB do
  @moduledoc """
  BGP RIBs

  Implements operations needed to store and update RIB tables using ETS.
  """

  @type t :: :ets.table()
  @type key :: term()
  @type entry :: tuple()
  @type name :: atom()

  @spec new(name()) :: t()
  def new(table), do: :ets.new(table, [:set, :protected])

  @spec delete(t(), key()) :: true
  def delete(table, key), do: :ets.delete(table, key)

  @spec dump(t()) :: [entry()]
  def dump(table), do: :ets.tab2list(table)

  @spec reduce(t(), term(), (entry(), term() -> term())) :: term()
  def reduce(table, acc, fun), do: :ets.foldl(fun, acc, table)

  @spec upsert(t(), entry()) :: true
  def upsert(table, entry), do: :ets.insert(table, entry)
end
