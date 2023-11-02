import Config

config :logger, level: :debug

config :bgp, BGP.MyServer,
  asn: 65_536,
  bgp_id: "172.16.1.3",
  networks: ["12.12.0.0/20"],
  port: 179,
  peers: [
    [
      asn: 64496,
      bgp_id: "172.16.1.4",
      host: "172.16.1.4"
    ]
  ]
