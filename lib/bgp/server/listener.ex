defmodule BGP.Server.Listener do
  @moduledoc false

  alias ThousandIsland.{Handler, Socket}

  use Handler

  alias BGP.{FSM, Message, Prefix, Server}
  alias BGP.Message.{NOTIFICATION, OPEN}
  alias BGP.Server.Session

  require Logger

  @type t :: GenServer.server()

  @spec connection_for(Server.t(), Prefix.t()) :: {:ok, GenServer.server()} | {:error, :not_found}
  def connection_for(server, host) do
    case Registry.lookup(BGP.Server.Listener.Registry, {server, host}) do
      [] -> {:error, :not_found}
      [{pid, _value}] -> {:ok, pid}
    end
  end

  @spec outbound_connection(t(), Prefix.t()) :: :ok | {:error, :collision}
  def outbound_connection(handler, peer_bgp_id),
    do: GenServer.call(handler, {:outbound_connection, peer_bgp_id})

  @impl Handler
  def handle_connection(socket, server) do
    state = %{buffer: <<>>, fsm: nil, server: server}
    %{address: address} = Socket.peer_info(socket)

    with {:ok, state, peer} <- get_configured_peer(state, server, address),
         {:ok, state} <- trigger_event(state, socket, {:start, :automatic, :passive}),
         {:ok, state} <- trigger_event(state, socket, {:tcp_connection, :confirmed}),
         :ok <- register_handler(state, server, peer),
         do: {:continue, state}
  end

  @impl Handler
  def handle_data(data, socket, %{buffer: buffer, fsm: fsm} = state) do
    (buffer <> data)
    |> Message.stream!(fsm)
    |> Enum.reduce({:continue, state}, fn {rest, msg}, {:continue, state} ->
      with {:ok, state} <- trigger_event(state, socket, {:recv, msg}),
           do: {:continue, %{state | buffer: rest}}
    end)
  catch
    {:error, %NOTIFICATION{} = error} ->
      process_effect(state, socket, {:send, error})
      {:close, state}
  end

  @impl GenServer
  def handle_info({:timer, _timer, :expired} = event, {socket, state}) do
    case trigger_event(state, socket, event) do
      {:ok, state} -> {:noreply, {socket, state}}
      {action, state} -> {:stop, {:error, action}, {socket, state}}
    end
  end

  @impl GenServer
  def handle_call(
        {:outbound_connection, _peer_bgp_id},
        _from,
        {socket, %{fsm: %FSM{state: :established}} = state}
      ),
      do: {:reply, {:error, :collision}, {socket, state}}

  def handle_call(
        {:outbound_connection, peer_bgp_id},
        _from,
        {socket, %{options: options, fsm: %FSM{state: fsm_state}} = state}
      )
      when fsm_state in [:open_confirm, :open_sent] do
    server_bgp_id =
      options[:server]
      |> Server.get_config()
      |> Keyword.fetch!(:bgp_id)

    if server_bgp_id > peer_bgp_id do
      {:reply, {:error, :collision}, {socket, state}}
    else
      Logger.warn("LISTENER: closing connection to peer due to collision")

      case trigger_event(state, socket, {:error, :open_collision_dump}) do
        {:ok, state} -> {:stop, :normal, :ok, {socket, state}}
        {action, state} -> {:stop, {:error, action}, :ok, {socket, state}}
      end
    end
  end

  def handle_call({:incoming_connection, _peer_bgp_id}, _from, {socket, state}),
    do: {:reply, :ok, {socket, state}}

  defp get_configured_peer(state, server, address) do
    case Server.get_peer(server, address) do
      {:ok, peer} ->
        {:ok, %{state | fsm: FSM.new(Server.get_config(server), peer)}, peer}

      {:error, :not_found} ->
        Logger.warn("LISTENER: dropping connection, no configured peer for #{inspect(address)}")
        {:close, state}
    end
  end

  defp register_handler(state, server, peer) do
    case Registry.register(BGP.Server.Listener.Registry, {server, peer[:host]}, nil) do
      {:ok, _pid} ->
        :ok

      {:error, _reason} ->
        Logger.warn("LISTENER: dropping connection, connection already exists for #{peer[:host]}")
        {:close, state}
    end
  end

  defp trigger_event(%{fsm: fsm} = state, socket, event) do
    Logger.debug("LISTENER: Triggering FSM event: #{inspect(event)}")

    with {:ok, fsm, effects} <- FSM.event(fsm, event),
         do: process_effects(%{state | fsm: fsm}, socket, effects)
  end

  defp process_effects(state, socket, effects) do
    Logger.debug("LISTENER: Processing FSM effects: #{inspect(effects)}")

    Enum.reduce(effects, {:ok, state}, fn effect, return ->
      case process_effect(state, socket, effect) do
        :ok ->
          return

        {action, state} ->
          {action, state}
      end
    end)
  end

  defp process_effect(%{server: server} = state, socket, {:recv, %OPEN{} = open}) do
    %{address: address} = Socket.peer_info(socket)

    with {:ok, session} <- Session.session_for(server, address),
         :ok <- Session.incoming_connection(session, open.bgp_id) do
      Logger.debug("LISTENER: No collision, keeping connection from peer #{inspect(address)}")
      :ok
    else
      {:error, :collision} ->
        Logger.warn("LISTENER: Connection from peer #{inspect(address)} collides, closing")

        case trigger_event(state, socket, {:error, :open_collision_dump}) do
          {:ok, state} -> {:close, state}
          {action, state} -> {action, state}
        end

      {:error, :not_found} ->
        Logger.warn("LISTENER: No configured session for peer #{inspect(address)}, closing")
        {:close, state}
    end
  end

  defp process_effect(_state, _socket, {:recv, _msg}), do: :ok

  defp process_effect(%{fsm: fsm} = state, socket, {:send, msg}) do
    case Socket.send(socket, Message.encode(msg, fsm)) do
      :ok -> :ok
      {:error, _reason} -> {:close, state}
    end
  end

  defp process_effect(state, _socket, {:tcp_connection, :disconnect}), do: {:close, state}
end
