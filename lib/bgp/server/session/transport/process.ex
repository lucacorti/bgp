defmodule BGP.Server.Session.Transport.Process do
  @moduledoc "TCP Transport"

  alias BGP.Message
  alias BGP.Server
  alias BGP.Server.Session
  alias BGP.Server.Session.Transport

  @behaviour Transport

  @impl Transport
  def connect(%Session{} = data) do
    with {:ok, pid} <-
           Server.session_for(data.transport_opts[:server], data.bgp_id),
         :ok <- :gen_statem.call(pid, {:process_connect}) do
      {:ok, pid}
    end
  end

  @impl Transport
  def disconnect(%Session{} = data) do
    with {:ok, pid} <- Server.session_for(data.transport_opts[:server], data.bgp_id),
         do: :gen_statem.call(pid, {:process_disconnect})
  end

  @impl Transport
  def send(%Session{} = data, msg) do
    {_msg_data, data} = Message.encode(msg, data)

    with :ok <- :gen_statem.cast(data.socket, {:process_recv, msg}), do: {:ok, data}
  end
end
