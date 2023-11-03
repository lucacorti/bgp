defmodule BGP.Server do
  @moduledoc "BGP Server"

  @peer_schema as_origination: [
                 type: :keyword_list,
                 keys: [
                   seconds: [
                     doc: "AS Origination timer seconds.",
                     type: :non_neg_integer
                   ]
                 ],
                 default: [seconds: 15]
               ],
               asn: [
                 doc: "Peer Autonomous System Number.",
                 type: :pos_integer,
                 default: 23_456
               ],
               bgp_id: [
                 doc: "Peer BGP ID, IP address.",
                 type: :string,
                 required: true
               ],
               connect_retry: [
                 type: :keyword_list,
                 keys: [
                   seconds: [doc: "Connect Retry timer seconds.", type: :non_neg_integer]
                 ],
                 default: [seconds: 120]
               ],
               delay_open: [
                 type: :keyword_list,
                 keys: [
                   enabled?: [doc: "Enable Delay OPEN.", type: :boolean],
                   seconds: [doc: "Delay OPEN timer seconds.", type: :non_neg_integer]
                 ],
                 default: [enabled?: true, seconds: 5]
               ],
               hold_time: [
                 type: :keyword_list,
                 keys: [
                   seconds: [doc: "Hold Time timer seconds.", type: :non_neg_integer]
                 ],
                 default: [seconds: 90]
               ],
               host: [
                 doc: "Peer IP address as string.",
                 type: {:custom, IP.Address, :from_string, []},
                 required: true
               ],
               keep_alive: [
                 type: :keyword_list,
                 keys: [
                   seconds: [doc: "Keep Alive timer seconds.", type: :non_neg_integer]
                 ],
                 default: [seconds: 30]
               ],
               notification_without_open: [
                 doc: "Allows NOTIFICATIONS to be received without OPEN first.",
                 type: :boolean,
                 default: true
               ],
               mode: [
                 doc: "Actively connects to the peer or just waits for a connection.",
                 type: {:in, [:active, :passive]},
                 default: :active
               ],
               port: [
                 doc: "Peer TCP port.",
                 type: :integer,
                 default: 179
               ],
               route_advertisement: [
                 type: :keyword_list,
                 keys: [
                   seconds: [
                     doc: "Route Advertisement timer seconds.",
                     type: :non_neg_integer
                   ]
                 ],
                 default: [seconds: 30]
               ],
               start: [
                 doc: "Type of session startup.",
                 type: {:in, [:automatic, :manual]},
                 default: :automatic
               ]

  @server_schema asn: [
                   doc: "Server Autonomous System Number.",
                   type: :pos_integer,
                   required: true
                 ],
                 bgp_id: [
                   doc: "Server BGP ID, IP address as string.",
                   type: {:custom, IP.Address, :from_string, []},
                   required: true
                 ],
                 networks: [
                   doc: "Server AS Networks to announce to peers",
                   type: {:list, {:custom, IP.Prefix, :from_string, []}},
                   default: []
                 ],
                 port: [
                   doc: "Port the server listens on.",
                   type: :integer,
                   default: 179
                 ],
                 peers: [
                   doc: "List of peer configurations (`t:peer_options/0`).",
                   type: {:list, {:keyword_list, @peer_schema}},
                   default: []
                 ],
                 transport: [
                   doc:
                     "Server transport. Allows to use a transport different from TCP. Not normally needed.",
                   type: :atom,
                   default: BGP.Server.Session.Transport.TCP
                 ]
  @typedoc """
  Server options

  #{NimbleOptions.docs(@server_schema)}
  """
  @type options :: keyword()

  @typedoc """
  Peer options

  #{NimbleOptions.docs(@peer_schema)}
  """
  @type peer_options :: keyword()

  @typedoc "BGP Server"
  @type t :: module()

  use Supervisor

  defmacro __using__(otp_app: otp_app) when is_atom(otp_app) do
    quote do
      @__otp_app__ unquote(otp_app)
      def __otp_app__, do: @__otp_app__
    end
  end

  defmacro __using__(_args) do
    raise "You must pass a module name to #{__MODULE__} :otp_app option"
  end

  @doc false
  def child_spec([server: server] = opts),
    do: %{id: server, type: :supervisor, start: {__MODULE__, :start_link, [opts]}}

  @impl Supervisor
  def init(args) do
    server = args[:server]

    Supervisor.init(
      [
        {Registry, keys: :unique, name: session_registry(server)},
        {BGP.Server.RDE, server: server},
        {
          ThousandIsland,
          port: args[:port], handler_module: BGP.Server.Session, handler_options: args
        }
        | Enum.map(args[:peers], &{BGP.Server.Session, &1})
      ],
      strategy: :one_for_all
    )
  end

  @spec start_link(keyword) :: Supervisor.on_start()
  def start_link(server: server) do
    Supervisor.start_link(__MODULE__, get_config(server), name: server)
  end

  @spec get_config(t()) :: keyword()
  def get_config(server) do
    config = :persistent_term.get(server, nil)

    if is_nil(config) do
      config =
        server.__otp_app__()
        |> Application.get_env(server, [])
        |> NimbleOptions.validate!(@server_schema)
        |> Keyword.put(:server, server)
        |> Keyword.update!(
          :peers,
          &Enum.map(&1, fn peer -> Keyword.put(peer, :server, server) end)
        )

      :ok = :persistent_term.put(server, config)
      config
    else
      config
    end
  end

  @spec get_peer(t(), IP.Address.t()) :: {:ok, keyword()} | {:error, :not_found}
  def get_peer(server, host) do
    server
    |> get_config()
    |> Keyword.get(:peers, [])
    |> Enum.find_value({:error, :not_found}, fn peer ->
      if host == peer[:host], do: {:ok, peer}
    end)
  end

  @spec session_for(BGP.Server.t(), IP.Address.t()) ::
          {:ok, GenServer.server()} | {:error, :not_found}
  def session_for(server, host) do
    case Registry.lookup(session_registry(server), host) do
      [] -> {:error, :not_found}
      [{pid, _value}] -> {:ok, pid}
    end
  end

  @spec session_registry(t()) :: module()
  def session_registry(server), do: Module.concat(server, Session.Registry)
end
