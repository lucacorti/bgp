defmodule BGP.Server.RDE.RIB do
  @moduledoc false

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

  @spec upsert(t(), entry()) :: true
  def upsert(table, entry), do: :ets.insert(table, entry)
end
