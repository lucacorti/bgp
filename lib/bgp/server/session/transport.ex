defmodule BGP.Server.Session.Transport do
  @moduledoc """
  Session Transport
  """

  alias BGP.Message
  alias BGP.Server.Session

  @type t :: module()
  @type socket :: term()

  @callback connect(Session.data()) :: {:ok, socket()} | {:error, term()}
  @callback disconnect(Session.data()) :: :ok | {:error, term()}
  @callback send(Session.data(), Message.t()) :: {:ok, Session.data()} | {:error, term()}
end
