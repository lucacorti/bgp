defmodule BGP.FSM do
  @moduledoc false

  alias BGP.{FSM.Timer, Message, Server}
  alias BGP.Message.{KEEPALIVE, NOTIFICATION, OPEN, UPDATE}
  alias BGP.Message.OPEN.Parameter.Capabilities

  require Logger

  @asn_2octets_max 65_535
  @asn_trans 23_456

  @type connection_op :: :connect | :disconnect
  @type msg_op :: :recv | :send
  @type effect :: {msg_op(), Message.t()} | {:tcp_connection, connection_op()}
  @type start_type :: :manual | :automatic
  @type start_passivity :: :active | :passive
  @type connection_event :: :confirmed | :fails | :request_acked
  @type timer_event :: :expired

  @type event ::
          {msg_op(), Message.t()}
          | {:error, :open_collision_dump}
          | {:tcp_connection, connection_event()}
          | {:start, start_type(), start_passivity()}
          | {:stop, start_type()}
          | {:timer, Timer.name(), timer_event()}

  @type counter :: pos_integer()
  @type state :: :idle | :active | :open_sent | :open_confirm | :established

  @type t :: %__MODULE__{
          asn: BGP.asn(),
          bgp_id: BGP.bgp_id(),
          counters: keyword(counter()),
          delay_open: boolean(),
          delay_open_time: non_neg_integer(),
          extended_message: boolean(),
          four_octets: boolean(),
          hold_time: BGP.hold_time(),
          internal: boolean(),
          notification_without_open: boolean(),
          options: Server.peer_options(),
          state: state(),
          timers: keyword(Timer.t())
        }

  @enforce_keys [
    :asn,
    :bgp_id,
    :delay_open,
    :delay_open_time,
    :hold_time,
    :notification_without_open,
    :options
  ]
  defstruct asn: nil,
            bgp_id: nil,
            counters: [connect_retry: 0],
            delay_open: nil,
            delay_open_time: nil,
            extended_message: false,
            four_octets: false,
            hold_time: nil,
            internal: false,
            notification_without_open: nil,
            options: [],
            state: :idle,
            timers: [
              connect_retry: Timer.new(0),
              delay_open: Timer.new(0),
              hold_time: Timer.new(0),
              keep_alive: Timer.new(0)
            ]

  @spec new(Server.options(), Server.peer_options()) :: t()
  def new(server, peer) do
    struct(__MODULE__,
      asn: server[:asn],
      bgp_id: server[:bgp_id],
      delay_open: peer[:delay_open][:enabled],
      delay_open_time: peer[:delay_open][:seconds],
      hold_time: peer[:hold_time][:seconds],
      notification_without_open: peer[:notification_without_open],
      options: peer
    )
  end

  @spec event(t(), event()) :: {:ok, t(), [effect()]}
  def event(%{state: old_state} = fsm, event) do
    with {:ok, fsm, effects} <- process_event(fsm, event) do
      Logger.debug("FSM state: #{old_state} -> #{fsm.state}")
      {:ok, fsm, effects}
    end
  end

  defp process_event(%__MODULE__{state: :idle} = fsm, {:stop, _type}),
    do: {:ok, fsm, []}

  defp process_event(%__MODULE__{state: :idle} = fsm, {:start, _type, :active}),
    do: {
      :ok,
      %__MODULE__{fsm | state: :connect}
      |> zero_counter(:connect_retry)
      |> restart_timer(:connect_retry),
      [{:tcp_connection, :connect}]
    }

  defp process_event(%__MODULE__{state: :idle} = fsm, {:start, _type, :passive}),
    do: {
      :ok,
      %__MODULE__{fsm | state: :active}
      |> zero_counter(:connect_retry)
      |> restart_timer(:connect_retry),
      []
    }

  defp process_event(%__MODULE__{state: :idle} = fsm, _event), do: {:ok, fsm, []}

  defp process_event(%__MODULE__{state: :connect} = fsm, {:start, _type, _passivity}),
    do: {:ok, fsm, []}

  defp process_event(%__MODULE__{state: :connect} = fsm, {:stop, :manual}),
    do: {
      :ok,
      %__MODULE__{fsm | state: :idle}
      |> zero_counter(:connect_retry)
      |> stop_timer(:connect_retry)
      |> set_timer(:connect_retry, 0),
      [{:tcp_connection, :disconnect}]
    }

  defp process_event(%__MODULE__{state: :connect} = fsm, {:timer, :connect_retry, :expired}),
    do: {
      :ok,
      fsm
      |> restart_timer(:connect_retry)
      |> stop_timer(:delay_open)
      |> set_timer(:delay_open, 0),
      [{:tcp_connection, :connect}]
    }

  defp process_event(%__MODULE__{state: :connect} = fsm, {:timer, :delay_open, :expired}) do
    {
      :ok,
      %__MODULE__{fsm | state: :open_sent}
      |> set_timer(:hold_time),
      [{:send, compose_open(fsm)}]
    }
  end

  defp process_event(
         %__MODULE__{delay_open: true, state: :connect} = fsm,
         {:tcp_connection, event}
       )
       when event in [:confirmed, :request_acked] do
    {
      :ok,
      fsm
      |> stop_timer(:connect_retry)
      |> set_timer(:connect_retry, 0)
      |> restart_timer(:delay_open),
      []
    }
  end

  defp process_event(
         %__MODULE__{delay_open: false, state: :connect} = fsm,
         {:tcp_connection, event}
       )
       when event in [:confirmed, :request_acked] do
    {
      :ok,
      %__MODULE__{fsm | state: :open_sent}
      |> stop_timer(:connect_retry)
      |> set_timer(:connect_retry, 0)
      |> set_timer(:hold_time),
      [{:send, compose_open(fsm)}]
    }
  end

  defp process_event(%__MODULE__{state: :connect} = fsm, {:tcp_connection, :fails}) do
    if timer_running?(fsm, :delay_open) do
      {
        :ok,
        %__MODULE__{fsm | state: :active}
        |> restart_timer(:connect_retry)
        |> stop_timer(:delay_open)
        |> set_timer(:delay_open, 0),
        []
      }
    else
      {
        :ok,
        %__MODULE__{fsm | state: :idle}
        |> stop_timer(:connect_retry)
        |> set_timer(:connect_retry, 0),
        []
      }
    end
  end

  defp process_event(%__MODULE__{state: :connect} = fsm, {:recv, msg}) do
    delay_open_timer_running = timer_running?(fsm, :delay_open)

    case msg do
      %OPEN{hold_time: hold_time} = open when delay_open_timer_running ->
        fsm =
          if hold_time > 0 do
            fsm
            |> restart_timer(:keep_alive, div(hold_time, 3))
            |> restart_timer(:hold_time, hold_time)
          else
            fsm
            |> restart_timer(:keep_alive)
            |> set_timer(:hold_time)
          end

        {
          :ok,
          %__MODULE__{fsm | state: :open_confirm}
          |> process_open(open)
          |> stop_timer(:connect_retry)
          |> set_timer(:connect_retry, 0)
          |> stop_timer(:delay_open)
          |> set_timer(:delay_open, 0),
          [
            {:recv, open},
            {:send, compose_open(fsm)},
            {:send, %KEEPALIVE{}}
          ]
        }

      %NOTIFICATION{code: :unsupported_version_number} when delay_open_timer_running ->
        {
          :ok,
          %__MODULE__{fsm | state: :idle}
          |> stop_timer(:connect_retry)
          |> set_timer(:connect_retry, 0)
          |> stop_timer(:delay_open)
          |> set_timer(:delay_open, 0),
          [{:tcp_connection, :disconnect}]
        }

      %NOTIFICATION{code: :unsupported_version_number} ->
        {
          :ok,
          %__MODULE__{fsm | state: :idle}
          |> stop_timer(:connect_retry)
          |> set_timer(:connect_retry, 0)
          |> increment_counter(:connect_retry),
          [{:tcp_connection, :disconnect}]
        }
    end
  end

  defp process_event(%__MODULE__{state: :connect} = fsm, _event) do
    {
      :ok,
      %__MODULE__{fsm | state: :idle}
      |> stop_timer(:connect_retry)
      |> set_timer(:connect_retry, 0)
      |> stop_timer(:delay_open)
      |> set_timer(:delay_open, 0)
      |> increment_counter(:connect_retry),
      []
    }
  end

  defp process_event(%__MODULE__{state: :active} = fsm, {:start, _type, _passivity}),
    do: {:ok, fsm, []}

  defp process_event(
         %__MODULE__{notification_without_open: true, state: :active} = fsm,
         {:stop, :manual}
       ) do
    {
      :ok,
      %__MODULE__{fsm | state: :idle}
      |> stop_timer(:delay_open)
      |> zero_counter(:connect_retry)
      |> stop_timer(:connect_retry)
      |> set_timer(:connect_retry, 0),
      [
        {:send, %NOTIFICATION{code: :cease}},
        {:tcp_connection, :disconnect}
      ]
    }
  end

  defp process_event(%__MODULE__{state: :active} = fsm, {:stop, :manual}) do
    {
      :ok,
      %__MODULE__{fsm | state: :idle}
      |> stop_timer(:delay_open)
      |> zero_counter(:connect_retry)
      |> stop_timer(:connect_retry)
      |> set_timer(:connect_retry, 0),
      [{:tcp_connection, :disconnect}]
    }
  end

  defp process_event(%__MODULE__{state: :active} = fsm, {:timer, :connect_retry, :expired}) do
    {
      :ok,
      %__MODULE__{fsm | state: :connect}
      |> restart_timer(:connect_retry),
      []
    }
  end

  defp process_event(%__MODULE__{state: :active} = fsm, {:timer, :delay_open, :expired}) do
    {
      :ok,
      %__MODULE__{fsm | state: :open_sent}
      |> set_timer(:connect_retry, 0)
      |> stop_timer(:delay_open)
      |> set_timer(:delay_open, 0)
      |> set_timer(:hold_time),
      [{:send, compose_open(fsm)}]
    }
  end

  defp process_event(
         %__MODULE__{delay_open: true, state: :active} = fsm,
         {:tcp_connection, event}
       )
       when event in [:confirmed, :request_acked] do
    {
      :ok,
      fsm
      |> stop_timer(:connect_retry)
      |> set_timer(:connect_retry, 0)
      |> restart_timer(:delay_open),
      []
    }
  end

  defp process_event(
         %__MODULE__{delay_open: false, state: :active} = fsm,
         {:tcp_connection, event}
       )
       when event in [:confirmed, :request_acked] do
    {
      :ok,
      %__MODULE__{fsm | state: :open_sent}
      |> set_timer(:connect_retry, 0)
      |> set_timer(:hold_time),
      [{:send, compose_open(fsm)}]
    }
  end

  defp process_event(%__MODULE__{state: :active} = fsm, {:tcp_connection, :fails}),
    do: {
      :ok,
      %__MODULE__{fsm | state: :idle}
      |> restart_timer(:connect_retry, 0)
      |> stop_timer(:delay_open)
      |> set_timer(:delay_open, 0)
      |> increment_counter(:connect_retry),
      []
    }

  defp process_event(%__MODULE__{state: :active} = fsm, {:recv, msg}) do
    delay_open_timer_running = timer_running?(fsm, :delay_open)

    case msg do
      %OPEN{hold_time: hold_time} = open when delay_open_timer_running ->
        fsm =
          if hold_time > 0 do
            fsm
            |> restart_timer(:keep_alive, div(hold_time, 3))
            |> restart_timer(:hold_time, hold_time)
          else
            fsm
            |> set_timer(:keep_alive, 0)
            |> set_timer(:hold_time, 0)
          end

        {
          :ok,
          %__MODULE__{fsm | state: :open_confirm}
          |> process_open(open)
          |> stop_timer(:connect_retry)
          |> set_timer(:connect_retry, 0)
          |> stop_timer(:delay_open)
          |> set_timer(:delay_open, 0),
          [
            {:recv, open},
            {:send, compose_open(fsm)},
            {:send, %KEEPALIVE{}}
          ]
        }

      %NOTIFICATION{code: :unsupported_version_number} when delay_open_timer_running ->
        {
          :ok,
          %__MODULE__{fsm | state: :idle}
          |> stop_timer(:connect_retry)
          |> set_timer(:connect_retry, 0)
          |> stop_timer(:delay_open)
          |> set_timer(:delay_open, 0),
          [{:tcp_connection, :disconnect}]
        }

      %NOTIFICATION{code: :unsupported_version_number} ->
        {
          :ok,
          %__MODULE__{fsm | state: :idle}
          |> set_timer(:connect_retry, 0)
          |> increment_counter(:connect_retry),
          [{:tcp_connection, :disconnect}]
        }
    end
  end

  defp process_event(%__MODULE__{state: :active} = fsm, _event) do
    {
      :ok,
      %__MODULE__{fsm | state: :idle}
      |> set_timer(:connect_retry, 0)
      |> increment_counter(:connect_retry),
      [{:tcp_connection, :disconnect}]
    }
  end

  defp process_event(%__MODULE__{state: :open_sent} = fsm, {:start, _type, _passivity}),
    do: {:ok, fsm, []}

  defp process_event(%__MODULE__{state: :open_sent} = fsm, {:stop, :manual}) do
    {
      :ok,
      %__MODULE__{fsm | state: :idle}
      |> set_timer(:connect_retry, 0)
      |> zero_counter(:connect_retry),
      [
        {:send, %NOTIFICATION{code: :cease}}
      ]
    }
  end

  defp process_event(%__MODULE__{state: :open_sent} = fsm, {:stop, :automatic}) do
    {
      :ok,
      %__MODULE__{fsm | state: :idle}
      |> set_timer(:connect_retry, 0)
      |> increment_counter(:connect_retry),
      [
        {:send, %NOTIFICATION{code: :cease}},
        {:tcp_connection, :disconnect}
      ]
    }
  end

  defp process_event(%__MODULE__{state: :open_sent} = fsm, {:timer, :hold_time, :expired}) do
    {
      :ok,
      %__MODULE__{fsm | state: :idle}
      |> set_timer(:connect_retry, 0)
      |> increment_counter(:connect_retry),
      [
        {:send, %NOTIFICATION{code: :hold_timer_expired}},
        {:tcp_connection, :disconnect}
      ]
    }
  end

  defp process_event(%__MODULE__{state: :open_sent} = fsm, {:tcp_connection, :fails}) do
    {
      :ok,
      %__MODULE__{fsm | state: :active}
      |> stop_timer(:connect_retry)
      |> start_timer(:connect_retry),
      [{:tcp_connection, :disconnect}]
    }
  end

  defp process_event(%__MODULE__{state: :open_sent} = fsm, {:error, :open_collision_dump}) do
    {
      :ok,
      %__MODULE__{fsm | state: :idle}
      |> set_timer(:connect_retry, 0)
      |> increment_counter(:connect_retry),
      [
        {:send, %NOTIFICATION{code: :cease}},
        {:tcp_connection, :disconnect}
      ]
    }
  end

  defp process_event(%__MODULE__{state: :open_sent} = fsm, {:recv, msg}) do
    case msg do
      %OPEN{hold_time: hold_time} = open when hold_time > 0 ->
        {
          :ok,
          %__MODULE__{fsm | state: :open_confirm}
          |> process_open(open)
          |> set_timer(:delay_open, 0)
          |> set_timer(:connect_retry, 0)
          |> restart_timer(:keep_alive, div(hold_time, 3))
          |> restart_timer(:hold_time, hold_time),
          [
            {:recv, open},
            {:send, %KEEPALIVE{}}
          ]
        }

      %OPEN{} = open ->
        {
          :ok,
          %__MODULE__{fsm | state: :open_confirm}
          |> process_open(open)
          |> set_timer(:delay_open, 0)
          |> set_timer(:connect_retry, 0)
          |> stop_timer(:keep_alive),
          [
            {:recv, open},
            {:send, %KEEPALIVE{}}
          ]
        }

      %NOTIFICATION{code: :unsupported_version_number} ->
        {
          :ok,
          %__MODULE__{fsm | state: :idle}
          |> set_timer(:connect_retry, 0),
          [{:tcp_connection, :disconnect}]
        }
    end
  end

  defp process_event(%__MODULE__{state: :open_sent} = fsm, _event) do
    {
      :ok,
      %__MODULE__{fsm | state: :idle}
      |> set_timer(:connect_retry, 0)
      |> increment_counter(:connect_retry),
      [
        {:send, %NOTIFICATION{code: :fsm}},
        {:tcp_connection, :disconnect}
      ]
    }
  end

  defp process_event(%__MODULE__{state: :open_confirm} = fsm, {:start, _type, _passivity}),
    do: {:ok, fsm, []}

  defp process_event(%__MODULE__{state: :open_confirm} = fsm, {:stop, :manual}) do
    {
      :ok,
      %__MODULE__{fsm | state: :idle}
      |> set_timer(:connect_retry, 0)
      |> zero_counter(:connect_retry),
      [
        {:send, %NOTIFICATION{code: :cease}},
        {:tcp_connection, :disconnect}
      ]
    }
  end

  defp process_event(%__MODULE__{state: :open_confirm} = fsm, {:stop, :automatic}) do
    {
      :ok,
      %__MODULE__{fsm | state: :idle}
      |> set_timer(:connect_retry, 0)
      |> increment_counter(:connect_retry),
      [
        {:send, %NOTIFICATION{code: :cease}},
        {:tcp_connection, :disconnect}
      ]
    }
  end

  defp process_event(%__MODULE__{state: :open_confirm} = fsm, {:timer, :hold_time, :expired}) do
    {
      :ok,
      %__MODULE__{fsm | state: :idle}
      |> set_timer(:connect_retry, 0)
      |> increment_counter(:connect_retry),
      [
        {:send, %NOTIFICATION{code: :hold_timer_expired}},
        {:tcp_connection, :disconnect}
      ]
    }
  end

  defp process_event(%__MODULE__{state: :open_confirm} = fsm, {:timer, :keep_alive, :expired}) do
    {
      :ok,
      fsm
      |> restart_timer(:keep_alive),
      [
        {:send, %KEEPALIVE{}}
      ]
    }
  end

  defp process_event(%__MODULE__{state: :open_confirm} = fsm, {:tcp_connection, :fails}) do
    {
      :ok,
      %__MODULE__{fsm | state: :idle}
      |> set_timer(:connect_retry, 0)
      |> increment_counter(:connect_retry),
      [{:tcp_connection, :disconnect}]
    }
  end

  defp process_event(
         %__MODULE__{state: :open_confirm} = fsm,
         {:recv, %NOTIFICATION{code: :unsupported_version_number}}
       ) do
    {
      :ok,
      %__MODULE__{fsm | state: :idle}
      |> set_timer(:connect_retry, 0),
      [{:tcp_connection, :disconnect}]
    }
  end

  defp process_event(%__MODULE__{state: :open_confirm} = fsm, {:error, :open_collision_dump}) do
    {
      :ok,
      %__MODULE__{fsm | state: :idle}
      |> set_timer(:connect_retry, 0)
      |> increment_counter(:connect_retry),
      [
        {:send, %NOTIFICATION{code: :cease}},
        {:tcp_connection, :disconnect}
      ]
    }
  end

  defp process_event(
         %__MODULE__{hold_time: hold_time, state: :open_confirm} = fsm,
         {:recv, msg}
       ) do
    case msg do
      %NOTIFICATION{} ->
        {
          :ok,
          %__MODULE__{fsm | state: :idle}
          |> set_timer(:connect_retry, 0)
          |> increment_counter(:connect_retry),
          [{:tcp_connection, :disconnect}]
        }

      %OPEN{} ->
        {
          :ok,
          %__MODULE__{fsm | state: :idle}
          |> set_timer(:connect_retry, 0)
          |> increment_counter(:connect_retry),
          [
            {:send, %NOTIFICATION{code: :cease}}
          ]
        }

      %KEEPALIVE{} ->
        {
          :ok,
          %__MODULE__{fsm | state: :established}
          |> restart_timer(:hold_time, hold_time),
          []
        }
    end
  end

  defp process_event(%__MODULE__{state: :open_confirm} = fsm, _event) do
    {
      :ok,
      %__MODULE__{fsm | state: :idle}
      |> set_timer(:connect_retry, 0)
      |> increment_counter(:connect_retry),
      [
        {:send, %NOTIFICATION{code: :fsm}},
        {:tcp_connection, :disconnect}
      ]
    }
  end

  defp process_event(%__MODULE__{state: :established} = fsm, {:start, _type, _passivity}),
    do: {:ok, fsm, []}

  defp process_event(%__MODULE__{state: :established} = fsm, {:stop, :manual}) do
    {
      :ok,
      %__MODULE__{fsm | state: :idle}
      |> set_timer(:connect_retry, 0)
      |> zero_counter(:connect_retry),
      [
        {:send, %NOTIFICATION{code: :cease}},
        {:tcp_connection, :disconnect}
      ]
    }
  end

  defp process_event(%__MODULE__{state: :established} = fsm, {:stop, :automatic}) do
    {
      :ok,
      %__MODULE__{fsm | state: :idle}
      |> set_timer(:connect_retry, 0)
      |> increment_counter(:connect_retry),
      [
        {:send, %NOTIFICATION{code: :cease}},
        {:tcp_connection, :disconnect}
      ]
    }
  end

  defp process_event(%__MODULE__{state: :established} = fsm, {:timer, :hold_time, :expired}) do
    {
      :ok,
      %__MODULE__{fsm | state: :idle}
      |> set_timer(:connect_retry, 0)
      |> increment_counter(:connect_retry),
      [
        {:send, %NOTIFICATION{code: :hold_timer_expired}},
        {:tcp_connection, :disconnect}
      ]
    }
  end

  defp process_event(
         %__MODULE__{hold_time: hold_time, state: :established} = fsm,
         {:timer, :keep_alive, :expired}
       ) do
    if hold_time > 0 do
      {
        :ok,
        fsm
        |> restart_timer(:keep_alive),
        [{:send, %KEEPALIVE{}}]
      }
    else
      {:ok, fsm, [{:send}], %KEEPALIVE{}}
    end
  end

  defp process_event(%__MODULE__{state: :established} = fsm, {:tcp_connection, :fails}) do
    {
      :ok,
      %__MODULE__{fsm | state: :idle}
      |> set_timer(:connect_retry, 0)
      |> increment_counter(:connect_retry),
      [{:tcp_connection, :disconnect}]
    }
  end

  defp process_event(%__MODULE__{state: :established} = fsm, {:error, :open_collision_dump}) do
    {
      :ok,
      %__MODULE__{fsm | state: :idle}
      |> set_timer(:connect_retry, 0)
      |> increment_counter(:connect_retry),
      [
        {:send, %NOTIFICATION{code: :cease}},
        {:tcp_connection, :disconnect}
      ]
    }
  end

  defp process_event(
         %__MODULE__{hold_time: hold_time, state: :established} = fsm,
         {:recv, msg}
       ) do
    case msg do
      %OPEN{} ->
        {
          :ok,
          %__MODULE__{fsm | state: :idle}
          |> set_timer(:connect_retry, 0)
          |> increment_counter(:connect_retry),
          [
            {:send, %NOTIFICATION{code: :cease}},
            {:tcp_connection, :disconnect}
          ]
        }

      %NOTIFICATION{} ->
        {
          :ok,
          %__MODULE__{fsm | state: :idle}
          |> set_timer(:connect_retry, 0)
          |> increment_counter(:connect_retry),
          [{:tcp_connection, :disconnect}]
        }

      %KEEPALIVE{} when hold_time > 0 ->
        {
          :ok,
          fsm
          |> restart_timer(:hold_time, hold_time),
          []
        }

      %KEEPALIVE{} ->
        {:ok, fsm, []}

      %UPDATE{} = msg when hold_time > 0 ->
        {
          :ok,
          fsm
          |> restart_timer(:hold_time, hold_time),
          [{:recv, msg}]
        }

      {:ok, %UPDATE{} = msg} ->
        {:ok, fsm, [{:recv}], msg}
    end
  end

  defp process_event(%__MODULE__{state: :established} = fsm, _event) do
    {
      :ok,
      %__MODULE__{fsm | state: :idle}
      |> set_timer(:connect_retry, 0)
      |> increment_counter(:connect_retry),
      [{:disconnect, %NOTIFICATION{code: :fsm}, :send}, {:tcp_connection}]
    }
  end

  defp compose_open(%__MODULE__{} = fsm) do
    %OPEN{
      asn: compose_open_asn(fsm),
      bgp_id: fsm.bgp_id,
      hold_time: fsm.hold_time,
      parameters: [
        %Capabilities{
          capabilities: [
            %Capabilities.FourOctetsASN{asn: fsm.asn},
            %Capabilities.MultiProtocol{afi: :ipv4, safi: :nlri_unicast}
          ]
        }
      ]
    }
  end

  defp compose_open_asn(%__MODULE__{asn: asn}) when asn < @asn_2octets_max, do: asn
  defp compose_open_asn(_fsm), do: @asn_trans

  defp process_open(fsm, %OPEN{} = open) do
    Enum.reduce(open.parameters, fsm, fn
      %Capabilities{capabilities: capabilities}, fsm ->
        process_open_capabilities(fsm, capabilities)

      _parameter, fsm ->
        fsm
    end)
  end

  defp process_open_capabilities(fsm, capabilities) do
    Enum.reduce(capabilities, fsm, fn
      %Capabilities.ExtendedMessage{}, fsm ->
        %__MODULE__{fsm | extended_message: true}

      %Capabilities.FourOctetsASN{asn: asn}, fsm ->
        %__MODULE__{fsm | four_octets: true, internal: asn == fsm.asn}

      _capability, fsm ->
        fsm
    end)
  end

  defp increment_counter(%__MODULE__{counters: counters} = fsm, name),
    do: %__MODULE__{fsm | counters: update_in(counters, [name], &(&1 + 1))}

  defp zero_counter(%__MODULE__{counters: counters} = fsm, name),
    do: %__MODULE__{fsm | counters: update_in(counters, [name], fn _ -> 0 end)}

  defp set_timer(%__MODULE__{options: options, timers: timers} = fsm, name, value \\ nil) do
    seconds = value || get_in(options, [name, :seconds])
    %__MODULE__{fsm | timers: update_in(timers, [name], &Timer.init(&1, seconds))}
  end

  defp restart_timer(fsm, name, value \\ nil) do
    fsm
    |> stop_timer(name)
    |> set_timer(name, value)
    |> start_timer(name)
  end

  defp start_timer(%__MODULE__{timers: timers} = fsm, name),
    do: %__MODULE__{fsm | timers: update_in(timers, [name], &Timer.start(&1, name))}

  defp stop_timer(%__MODULE__{timers: timers} = fsm, name),
    do: %__MODULE__{fsm | timers: update_in(timers, [name], &Timer.stop(&1))}

  defp timer_running?(%__MODULE__{timers: timers}, name),
    do: Timer.running?(get_in(timers, [name]))
end
