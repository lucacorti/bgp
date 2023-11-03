defmodule BGP.Server.Session.Transport.Process do
  @moduledoc "TCP Transport"

  alias BGP.Message
  alias BGP.Server
  alias BGP.Server.Session
  alias BGP.Server.Session.Transport

  @behaviour Transport

  @impl Transport
  def connect(%Session{} = data) do
    case Registry.lookup(Server.session_registry(data.server), data.host) do
      [] ->
        {:error, :not_found}

      [{pid, _value}] ->
        :gen_statem.call(pid, {:process_connect})
        {:ok, pid}
    end
  end

  @impl Transport
  def disconnect(%Session{} = data) do
    case Registry.lookup(Server.session_registry(data.server), data.host) do
      [] ->
        {:error, :not_found}

      [{pid, _value}] ->
        :gen_statem.call(pid, {:process_disconnect})
        {:ok, pid}
    end
  end

  @impl Transport
  def send(%Session{} = data, msg) do
    {_msg_data, data} = Message.encode(msg, data)

    case :gen_statem.call(data.socket, {:process_recv, msg}) do
      :ok -> {:ok, data}
      reason -> {:error, reason}
    end
  end
end
