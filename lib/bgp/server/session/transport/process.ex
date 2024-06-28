defmodule BGP.Server.Session.Transport.Process do
  @moduledoc "Process Transport"

  alias BGP.Message
  alias BGP.Server
  alias BGP.Server.Session
  alias BGP.Server.Session.Transport

  @behaviour Transport

  @impl Transport
  def connect(%Session{} = data) do
    server_config = Server.get_config(data.server)
    peer_server = data.transport_opts[:server]
    peer_server_session_supervisor = Server.session_supervisor(peer_server)

    with {:ok, peer} <- Server.get_peer(peer_server, server_config[:bgp_id]),
         peer = Keyword.merge(peer, start: :automatic, mode: :passive),
         {:ok, pid} <- Session.Supervisor.start_child(peer_server_session_supervisor, peer),
         :ok <- :gen_statem.call(pid, {:process_connect}) do
      {:ok, pid}
    end
  catch
    type, error ->
      {:error, {type, error}}
  end

  @impl Transport
  def close(%Session{} = data) do
    :gen_statem.call(data.socket, {:process_disconnect})
  catch
    type, error ->
      {:error, {type, error}}
  end

  @impl Transport
  def send(%Session{} = data, msg) do
    {_msg_data, data} = Message.encode(msg, data)
    with :ok <- :gen_statem.cast(data.socket, {:process_recv, msg}), do: {:ok, data}
  catch
    type, error ->
      {:error, {type, error}}
  end
end
