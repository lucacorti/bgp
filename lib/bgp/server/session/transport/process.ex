defmodule BGP.Server.Session.Transport.Process do
  @moduledoc "Process Transport"

  alias BGP.Message
  alias BGP.Server
  alias BGP.Server.Session
  alias BGP.Server.Session.Transport

  @behaviour Transport

  @impl Transport
  def connect(%Session{} = data) do
    with {:ok, pid} <- Server.session_for(data.transport_opts[:server], data.bgp_id),
         :ok <- :gen_statem.call(pid, {:process_accept}) do
      {:ok, pid}
    end
  catch
    type, error ->
      {:error, {type, error}}
  end

  @impl Transport
  def close(%Session{} = data) do
    with {:ok, pid} <- Server.session_for(data.transport_opts[:server], data.bgp_id),
         do: :gen_statem.call(pid, {:process_disconnect})
  catch
    type, error ->
      {:error, {type, error}}
  end

  @impl Transport
  def send(%Session{} = data, msg) do
    {_msg_data, data} = Message.encode(msg, data)

    with :ok <- :gen_statem.cast(data.socket, {:process_recv, msg}), do: {:ok, data}
  end
end
