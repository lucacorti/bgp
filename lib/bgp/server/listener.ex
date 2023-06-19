defmodule BGP.Server.Listener do
  @moduledoc false

  alias ThousandIsland.{Handler, Socket}

  use Handler

  alias BGP.{FSM, Message, Server}
  alias BGP.Message.{NOTIFICATION, OPEN, UPDATE}
  alias BGP.Server.Session

  require Logger

  @type t :: GenServer.server()

  @spec connection_for(Server.t(), IP.Address.t()) ::
          {:ok, GenServer.server()} | {:error, :not_found}
  def connection_for(server, host) do
    case Registry.lookup(Module.concat(server, Listener.Registry), host) do
      [] -> {:error, :not_found}
      [{pid, _value}] -> {:ok, pid}
    end
  end

  @spec outbound_connection(t(), IP.Address.t()) :: :ok | {:error, :collision}
  def outbound_connection(handler, peer_bgp_id),
    do: GenServer.call(handler, {:outbound_connection, peer_bgp_id})

  @impl Handler
  def handle_connection(socket, server) do
    state = %{buffer: <<>>, fsm: nil, server: server}

    with {:ok, {address, _port}} <- Socket.peername(socket),
         {:ok, host} <- IP.Address.from_tuple(address),
         {:ok, state, peer} <- get_configured_peer(state, server, host),
         {:ok, state} <- trigger_event(state, socket, {:start, :automatic, :passive}),
         {:ok, state} <- trigger_event(state, socket, {:tcp_connection, :confirmed}),
         :ok <- register_listener(state, server, peer),
         do: {:continue, state}
  end

  @impl Handler
  def handle_data(data, socket, %{buffer: buffer} = state) do
    (buffer <> data)
    |> Message.stream!()
    |> Enum.reduce({:continue, state}, fn {rest, data}, {:continue, %{fsm: fsm} = state} ->
      with {msg, fsm} <- Message.decode(data, fsm),
           {:ok, state} <- trigger_event(%{state | fsm: fsm}, socket, {:recv, msg}) do
        {:continue, %{state | buffer: rest}}
      end
    end)
  catch
    :error, %NOTIFICATION{} = error ->
      Logger.error("error while processing received message: #{inspect(error)}")

      case trigger_event(state, socket, {:send, error}) do
        {:ok, state} -> {:continue, state}
        {action, state} -> {action, state}
      end
  end

  @impl GenServer
  def handle_info({:timer, timer, :expired} = event, {socket, state}) do
    Logger.debug("LISTENER: #{timer} timer expired")

    case trigger_event(state, socket, event) do
      {:ok, state} -> {:noreply, {socket, state}}
      {action, state} -> {:stop, {:error, action}, {socket, state}}
    end
  end

  @impl GenServer
  def handle_call({:outbound_connection, peer_bgp_id}, _from, {socket, %{fsm: fsm} = state}) do
    case FSM.check_collision(fsm, peer_bgp_id) do
      :ok ->
        {:reply, :ok, {socket, state}}

      {:error, :collision} = error ->
        {:reply, error, {socket, state}}

      {:error, :close} ->
        Logger.warn("LISTENER: closing connection to peer due to collision")

        case trigger_event(state, socket, {:error, :open_collision_dump}) do
          {:ok, state} -> {:stop, :normal, :ok, {socket, state}}
          {action, state} -> {:stop, {:error, action}, :ok, {socket, state}}
        end
    end
  end

  defp get_configured_peer(state, server, address) do
    case Server.get_peer(server, address) do
      {:ok, peer} ->
        {:ok, %{state | fsm: FSM.new(Server.get_config(server), peer)}, peer}

      {:error, :not_found} ->
        Logger.warn("LISTENER: dropping connection, no configured peer for #{inspect(address)}")
        {:close, state}
    end
  end

  defp register_listener(state, server, peer) do
    case Registry.register(Module.concat(server, Listener.Registry), peer[:host], nil) do
      {:ok, _pid} ->
        :ok

      {:error, _reason} ->
        Logger.warn("LISTENER: dropping connection, connection already exists for #{peer[:host]}")
        {:close, state}
    end
  end

  defp trigger_event(%{fsm: fsm} = state, socket, event) do
    with {:ok, fsm, effects} <- FSM.event(fsm, event) do
      Enum.reduce(effects, {:ok, %{state | fsm: fsm}}, fn effect, {action, state} ->
        case process_effect(state, socket, effect) do
          {:ok, state} ->
            {action, state}

          {action, state} ->
            {action, state}
        end
      end)
    end
  end

  defp process_effect(%{server: server} = state, socket, {:recv, %OPEN{} = open}) do
    {:ok, {address, _port}} = Socket.peername(socket)

    with {:ok, host} <- IP.Address.from_tuple(address),
         {:ok, session} <- Session.session_for(server, host),
         :ok <- Session.incoming_connection(session, open.bgp_id) do
      Logger.debug("LISTENER: No collision, keeping connection from peer #{inspect(address)}")
      {:ok, state}
    else
      {:error, :collision} ->
        Logger.warn("LISTENER: Connection from peer #{inspect(address)} collides, closing")

        case trigger_event(state, socket, {:error, :open_collision_dump}) do
          {:ok, state} -> {:close, state}
          {action, state} -> {action, state}
        end

      {:error, reason} ->
        Logger.warn(
          "LISTENER: No configured session for peer #{inspect(address)}, closing (#{reason})"
        )

        {:close, state}
    end
  end

  defp process_effect(%{server: server} = state, _socket, {:recv, %UPDATE{} = message}) do
    with :ok <- Server.RDE.process_update(server, message), do: {:ok, state}
  end

  defp process_effect(%{fsm: fsm} = state, socket, {:send, msg}) do
    {data, fsm} = Message.encode(msg, fsm)

    case Socket.send(socket, data) do
      :ok -> {:ok, %{state | fsm: fsm}}
      {:error, _reason} -> {:close, %{state | fsm: fsm}}
    end
  end

  defp process_effect(state, _socket, {:tcp_connection, :disconnect}), do: {:close, state}
end
