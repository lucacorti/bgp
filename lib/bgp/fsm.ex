defmodule BGP.FSM do
  @moduledoc false

  alias BGP.{FSM.Timer, Message, Server}
  alias BGP.Message.{KEEPALIVE, NOTIFICATION, OPEN, UPDATE}
  alias BGP.Message.OPEN.Capabilities
  alias BGP.Message.UPDATE.Attribute
  alias BGP.Message.UPDATE.Attribute.{ASPath, NextHop, Origin}

  require Logger

  @asn_2octets_max 65_535
  @as_trans 23_456

  @type connection_event :: :confirmed | :fails | :request_acked
  @type connection_op :: :connect | :disconnect
  @type counter :: pos_integer()
  @type msg_op :: :recv | :send
  @type start_passivity :: :active | :passive
  @type start_type :: :manual | :automatic
  @type state :: :idle | :active | :open_sent | :open_confirm | :established
  @type timer_event :: :expired

  @type effect :: {msg_op(), Message.t()} | {:tcp_connection, connection_op()}

  @type event ::
          {msg_op(), Message.t()}
          | {:error, :open_collision_dump}
          | {:tcp_connection, connection_event()}
          | {:start, start_type(), start_passivity()}
          | {:stop, start_type()}
          | {:timer, Timer.name(), timer_event()}

  @type t :: %__MODULE__{
          as_origination_time: non_neg_integer(),
          asn: BGP.asn(),
          bgp_id: BGP.bgp_id(),
          counters: keyword(counter()),
          delay_open: boolean(),
          delay_open_time: non_neg_integer(),
          extended_message: boolean(),
          extended_optional_parameters: boolean(),
          four_octets: boolean(),
          hold_time: BGP.hold_time(),
          ibgp: boolean(),
          networks: [IP.Prefix.t()],
          notification_without_open: boolean(),
          options: Server.peer_options(),
          route_advertisement_time: non_neg_integer(),
          state: state(),
          timers: keyword(Timer.t())
        }

  @enforce_keys [
    :as_origination_time,
    :asn,
    :bgp_id,
    :delay_open,
    :delay_open_time,
    :hold_time,
    :notification_without_open,
    :options,
    :route_advertisement_time
  ]
  defstruct as_origination_time: nil,
            asn: nil,
            bgp_id: nil,
            counters: [connect_retry: 0],
            delay_open: nil,
            delay_open_time: nil,
            extended_message: false,
            extended_optional_parameters: false,
            four_octets: false,
            hold_time: nil,
            ibgp: false,
            networks: [],
            notification_without_open: nil,
            options: [],
            route_advertisement_time: nil,
            state: :idle,
            timers: [
              as_origination: Timer.new(0),
              connect_retry: Timer.new(0),
              delay_open: Timer.new(0),
              hold_time: Timer.new(0),
              keep_alive: Timer.new(0),
              route_advertisement: Timer.new(0)
            ]

  @spec new(Server.options(), Server.peer_options()) :: t()
  def new(server, peer) do
    struct(__MODULE__,
      as_origination_time: peer[:as_origination][:seconds],
      asn: server[:asn],
      bgp_id: server[:bgp_id],
      delay_open: peer[:delay_open][:enabled],
      delay_open_time: peer[:delay_open][:seconds],
      hold_time: peer[:hold_time][:seconds],
      networks: server[:networks],
      notification_without_open: peer[:notification_without_open],
      options: peer,
      route_advertisement_time: peer[:route_advertisement][:seconds]
    )
  end

  @spec event(t(), event()) :: {:ok, t(), [effect()]}
  def event(%{state: old_state} = fsm, event) do
    with {:ok, fsm, effects} <- process_event(fsm, event) do
      Logger.debug("FSM state: #{old_state} -> #{fsm.state}, effects: #{inspect(effects)}")
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

  defp process_event(%__MODULE__{state: :open_confirm} = fsm, {:recv, msg}) do
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
          |> restart_timer(:hold_time, fsm.hold_time)
          |> restart_timer(:as_origination, fsm.as_origination_time)
          |> restart_timer(:route_advertisement, fsm.route_advertisement_time),
          [{:send, compose_as_update(fsm)}]
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
      |> set_timer(:as_origination, 0)
      |> set_timer(:route_advertisement, 0)
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
      |> set_timer(:as_origination, 0)
      |> set_timer(:route_advertisement, 0)
      |> increment_counter(:connect_retry),
      [
        {:send, %NOTIFICATION{code: :cease}},
        {:tcp_connection, :disconnect}
      ]
    }
  end

  defp process_event(%__MODULE__{state: :established} = fsm, {:timer, :as_origination, :expired}) do
    {:ok, restart_timer(fsm, :as_origination), [{:send, compose_as_update(fsm)}]}
  end

  defp process_event(%__MODULE__{state: :established} = fsm, {:timer, :hold_time, :expired}) do
    {
      :ok,
      %__MODULE__{fsm | state: :idle}
      |> set_timer(:connect_retry, 0)
      |> set_timer(:as_origination, 0)
      |> set_timer(:route_advertisement, 0)
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
    fsm = if hold_time > 0, do: restart_timer(fsm, :keep_alive), else: fsm
    {:ok, fsm, [{:send, %KEEPALIVE{}}]}
  end

  defp process_event(
         %__MODULE__{state: :established} = fsm,
         {:timer, :route_advertisement, :expired}
       ) do
    {:ok, restart_timer(fsm, :route_advertisement), []}
  end

  defp process_event(%__MODULE__{state: :established} = fsm, {:tcp_connection, :fails}) do
    {
      :ok,
      %__MODULE__{fsm | state: :idle}
      |> set_timer(:connect_retry, 0)
      |> set_timer(:as_origination, 0)
      |> set_timer(:route_advertisement, 0)
      |> increment_counter(:connect_retry),
      [{:tcp_connection, :disconnect}]
    }
  end

  defp process_event(%__MODULE__{state: :established} = fsm, {:error, :open_collision_dump}) do
    {
      :ok,
      %__MODULE__{fsm | state: :idle}
      |> set_timer(:connect_retry, 0)
      |> set_timer(:as_origination, 0)
      |> set_timer(:route_advertisement, 0)
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
          |> set_timer(:as_origination, 0)
          |> set_timer(:route_advertisement, 0)
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
          |> set_timer(:as_origination, 0)
          |> set_timer(:route_advertisement, 0)
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
        {:ok, fsm, [{:recv, msg}]}
    end
  end

  defp process_event(%__MODULE__{state: :established} = fsm, _event) do
    {
      :ok,
      %__MODULE__{fsm | state: :idle}
      |> set_timer(:connect_retry, 0)
      |> set_timer(:as_origination, 0)
      |> set_timer(:route_advertisement, 0)
      |> increment_counter(:connect_retry),
      [{:send, %NOTIFICATION{code: :fsm}}, {:tcp_connection, :disconnect}]
    }
  end

  defp compose_open(%__MODULE__{} = fsm) do
    %OPEN{
      asn: compose_open_asn(fsm),
      bgp_id: fsm.bgp_id,
      hold_time: fsm.hold_time,
      capabilities: %Capabilities{
        four_octets_asn: true,
        multi_protocol: {:ipv4, :nlri_unicast},
        extended_message: true
      }
    }
  end

  defp compose_open_asn(%__MODULE__{asn: asn}) when asn < @asn_2octets_max, do: asn
  defp compose_open_asn(_fsm), do: @as_trans

  defp compose_as_update(%__MODULE__{} = fsm) do
    %UPDATE{
      path_attributes: [
        %Attribute{value: %Origin{origin: :igp}},
        %Attribute{value: %ASPath{value: [{:as_sequence, 1, [fsm.asn]}]}},
        %Attribute{value: %NextHop{value: fsm.bgp_id}}
      ],
      nlri: fsm.networks
    }
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
