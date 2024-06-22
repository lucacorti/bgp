defmodule BGP.Server.Session.Transport do
  @moduledoc """
  Session Transport
  """

  alias BGP.Message
  alias BGP.Server.Session

  @type t :: module()
  @type socket :: term()

  @callback close(Session.data()) :: :ok | {:error, term()}
  @callback connect(Session.data()) :: {:ok, socket()} | {:error, term()}
  @callback send(Session.data(), Message.t()) :: {:ok, Session.data()} | {:error, term()}
end
