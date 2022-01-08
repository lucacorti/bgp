defmodule BGP.Server.Listener do
  @moduledoc false

  alias ThousandIsland.{Handler, Socket}

  use Handler

  alias BGP.Message
  alias BGP.Message.{Encoder, OPEN}
  alias BGP.Server
  alias BGP.Server.{FSM, Session}

  require Logger

  @impl Handler
  def handle_connection(socket, server: server) do
    state = %{buffer: <<>>, fsm: FSM.new(Server.get_config(server)), server: server}
    %{address: address} = Socket.peer_info(socket)

    with {:ok, _peer} <- Server.get_peer(server, address),
         {:ok, state} <- trigger_event(state, socket, {:start, :automatic, :passive}),
         {:ok, state} <- trigger_event(state, socket, {:tcp_connection, :confirmed}),
         do: {:continue, state}
  end

  @impl Handler
  def handle_data(data, socket, %{buffer: buffer} = state) do
    (buffer <> data)
    |> Message.stream!()
    |> Enum.reduce({:continue, state}, fn {rest, msg}, {:continue, state} ->
      with {:ok, state} <- trigger_event(state, socket, {:msg, msg, :recv}),
           do: {:continue, %{state | buffer: rest}}
    end)
  catch
    %Encoder.Error{} = error ->
      data = Message.encode(Encoder.Error.to_notification(error), [])
      process_effect(state, socket, {:msg, data, :send})
      {:close, state}
  end

  @impl GenServer
  def handle_info({:timer, _timer, :expires} = event, {socket, state}) do
    with {:ok, state} <- trigger_event(state, socket, event),
         do: {:noreply, {socket, state}}
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

        {action, _reason} ->
          {action, state}
      end
    end)
  end

  defp process_effect(%{server: server} = state, socket, {:msg, %OPEN{bgp_id: bgp_id}, :recv}) do
    %{address: address} = Socket.peer_info(socket)

    with {:ok, session} <- Session.session_for(server, address),
         :ok <- Session.incoming_connection(session, bgp_id) do
      :ok
    else
      {:error, _} ->
        with {:ok, _state} <- trigger_event(state, socket, {:open, :collision_dump}),
             do: {:close, :collision}
    end
  end

  defp process_effect(_state, _socket, {:msg, _msg, :recv}), do: :ok

  defp process_effect(_state, socket, {:msg, data, :send}) do
    case Socket.send(socket, data) do
      :ok -> :ok
      {:error, reason} -> {:close, reason}
    end
  end

  defp process_effect(_state, _socket, {:tcp_connection, :disconnect}), do: {:close, :disconnect}
end
