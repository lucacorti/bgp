defmodule BGP.Server.Listener do
  @moduledoc false

  alias ThousandIsland.{Handler, Socket}

  use Handler

  alias BGP.{Message, Prefix, Server}
  alias BGP.Message.{Encoder.Error, OPEN}
  alias BGP.Server.{FSM, Session}

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
  def handle_connection(socket, server: server) do
    state = %{buffer: <<>>, fsm: FSM.new(Server.get_config(server)), server: server}
    %{address: address} = Socket.peer_info(socket)

    with {:ok, peer} <- get_configured_peer(state, server, address),
         {:ok, state} <- trigger_event(state, socket, {:start, :automatic, :passive}),
         {:ok, state} <- trigger_event(state, socket, {:tcp_connection, :confirmed}),
         :ok <- register_handler(state, server, peer),
         do: {:continue, state}
  end

  @impl Handler
  def handle_data(data, socket, %{buffer: buffer, fsm: fsm} = state) do
    (buffer <> data)
    |> Message.stream!(FSM.options(fsm))
    |> Enum.reduce({:continue, state}, fn {rest, msg}, {:continue, state} ->
      with {:ok, state} <- trigger_event(state, socket, {:msg, msg, :recv}),
           do: {:continue, %{state | buffer: rest}}
    end)
  catch
    %Error{} = error ->
      data = Message.encode(Error.to_notification(error), [])
      process_effect(state, socket, {:msg, data, :send})
      {:close, state}
  end

  @impl GenServer
  def handle_info({:timer, _timer, :expires} = event, {socket, state}) do
    case trigger_event(state, socket, event) do
      {:ok, state} ->
        {:noreply, {socket, state}}

      {action, state} ->
        {:stop, {:error, action}, {socket, state}}
    end
  end

  @impl GenServer
  def handle_call(
        {:outbound_connection, peer_bgp_id},
        _from,
        {socket, %{options: options} = state}
      ) do
    server_bgp_id =
      options
      |> Keyword.get(:server)
      |> Server.get_config(:bgp_id)

    if server_bgp_id > peer_bgp_id do
      {:reply, {:error, :collision}, {socket, state}}
    else
      Logger.warn("LISTENER: closing connection to peer due to collision")

      case trigger_event(state, socket, {:open, :collision_dump}) do
        {:ok, state} ->
          {:stop, :normal, :ok, {socket, state}}

        {action, state} ->
          {:stop, {:error, action}, :ok, {socket, state}}
      end
    end
  end

  defp get_configured_peer(state, server, address) do
    case Server.get_peer(server, address) do
      {:ok, peer} ->
        {:ok, peer}

      {:error, :not_found} ->
        Logger.warn("LISTENER: dropping connection, no configured peer for #{inspect(address)}")
        {:close, state}
    end
  end

  defp register_handler(state, server, peer) do
    host = Keyword.get(peer, :host)

    case Registry.register(BGP.Server.Listener.Registry, {server, host}, nil) do
      {:ok, _pid} ->
        :ok

      {:error, _reason} ->
        Logger.warn("LISTENER: dropping connection, connection already exists for #{host}")
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

  defp process_effect(%{server: server} = state, socket, {:msg, %OPEN{} = open, :recv}) do
    %{address: address} = Socket.peer_info(socket)

    with {:ok, session} <- Session.session_for(server, address),
         :ok <- Session.incoming_connection(session, open.bgp_id) do
      Logger.debug("No collision, keeping connection from peer #{inspect(address)}")
      :ok
    else
      {:error, :collision} ->
        Logger.warn("Connection from peer #{inspect(address)} collides, closing")

        with {:ok, state} <- trigger_event(state, socket, {:open, :collision_dump}),
             do: {:close, state}

      {:error, :not_found} ->
        Logger.warn("No configured session for peer #{inspect(address)}, closing")
        {:close, state}
    end
  end

  defp process_effect(_state, _socket, {:msg, _msg, :recv}), do: :ok

  defp process_effect(state, socket, {:msg, data, :send}) do
    case Socket.send(socket, data) do
      :ok -> :ok
      {:error, _reason} -> {:close, state}
    end
  end

  defp process_effect(state, _socket, {:tcp_connection, :disconnect}), do: {:close, state}
end
