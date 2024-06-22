defmodule BGP.Server.Session.Transport.TCP do
  @moduledoc "TCP Transport"

  alias BGP.Message
  alias BGP.Server.Session
  alias BGP.Server.Session.Transport

  alias ThousandIsland.Socket

  @behaviour Transport

  @impl Transport
  def connect(%Session{} = data) do
    host = IP.Address.to_string(data.host) |> String.to_charlist()
    :gen_tcp.connect(host, data.port, mode: :binary, active: :once)
  end

  @impl Transport
  def close(%Session{socket: %Socket{}} = data), do: Socket.close(data.socket)
  def close(%Session{} = data), do: :gen_tcp.close(data.socket)

  @impl Transport
  def send(%Session{socket: %Socket{}} = data, msg) do
    {msg_data, data} = Message.encode(msg, data)
    with :ok <- Socket.send(data.socket, msg_data), do: {:ok, data}
  end

  @impl Transport
  def send(%Session{} = data, msg) do
    {msg_data, data} = Message.encode(msg, data)
    with :ok <- :gen_tcp.send(data.socket, msg_data), do: {:ok, data}
  end
end
