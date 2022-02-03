defmodule BGP.Server do
  @moduledoc false

  use Supervisor

  alias BGP.Prefix

  @type t :: module()

  @options_schema NimbleOptions.new!(
                    asn: [
                      doc: "Server Autonomous System Number.",
                      type: :pos_integer,
                      required: true
                    ],
                    bgp_id: [
                      doc: "Server BGP ID, IP address as `:string`.",
                      type: {:custom, Prefix, :parse, []},
                      required: true
                    ],
                    connect_retry: [
                      type: :keyword_list,
                      keys: [
                        secs: [doc: "Connect Retry timer seconds.", type: :non_neg_integer]
                      ],
                      default: [secs: 120]
                    ],
                    delay_open: [
                      type: :keyword_list,
                      keys: [
                        enabled: [doc: "Enable Delay OPEN.", type: :boolean],
                        secs: [doc: "Delay OPEN timer seconds.", type: :non_neg_integer]
                      ],
                      default: [enabled: true, secs: 5]
                    ],
                    hold_time: [
                      type: :keyword_list,
                      keys: [secs: [doc: "Hold Time timer seconds.", type: :non_neg_integer]],
                      default: [secs: 90]
                    ],
                    keep_alive: [
                      type: :keyword_list,
                      keys: [secs: [doc: "Keep Alive timer seconds.", type: :non_neg_integer]],
                      default: [secs: 30]
                    ],
                    notification_without_open: [
                      doc: "Allows NOTIFICATIONS to be received without OPEN first",
                      type: :boolean,
                      default: true
                    ],
                    port: [
                      doc: "Peer TCP port.",
                      type: :integer,
                      default: 179
                    ],
                    peers: [
                      doc: "List peer configurations",
                      type: {:list, :keyword_list},
                      default: []
                    ]
                  )

  defmacro __using__(otp_app: otp_app) when is_atom(otp_app) do
    quote do
      @__otp_app__ unquote(otp_app)
      def __otp_app__, do: @__otp_app__
    end
  end

  defmacro __using__(_args),
    do: raise("You must pass a module name to #{__MODULE__} :otp_app option")

  def child_spec([server: server] = opts) do
    %{id: server, type: :supervisor, start: {__MODULE__, :start_link, [opts]}}
  end

  @spec start_link(keyword) :: Supervisor.on_start()
  def start_link(server: server) do
    options =
      server
      |> get_config()

    Supervisor.start_link(__MODULE__, options, name: server)
  end

  @spec get_config(t()) :: keyword()
  def get_config(server) do
    server.__otp_app__
    |> Application.get_env(server, [])
    |> NimbleOptions.validate!(@options_schema)
    |> Keyword.put(:server, server)
  end

  @spec get_config(t(), atom()) :: keyword()
  def get_config(server, key) do
    server
    |> get_config()
    |> Keyword.get(key)
  end

  @spec get_peer(t(), Prefix.t()) :: {:ok, keyword()} | {:error, :not_found}
  def get_peer(server, host) do
    server
    |> get_config()
    |> Keyword.get(:peers, [])
    |> Enum.find_value({:error, :not_found}, fn peer ->
      peer_host = Keyword.get(peer, :host)

      case Prefix.to_string(host) do
        {:ok, ^peer_host} -> {:ok, peer}
        {:error, :invalid} -> nil
      end
    end)
  end

  @impl Supervisor
  def init(args) do
    server = Keyword.take(args, [:server])
    port = Keyword.get(args, :port)

    peers =
      Enum.map(args[:peers], fn peer -> {BGP.Server.Session, Keyword.merge(peer, server)} end)

    Supervisor.init(
      peers ++
        [
          {ThousandIsland,
           port: port, handler_module: BGP.Server.Listener, handler_options: server}
        ],
      strategy: :one_for_all
    )
  end
end
