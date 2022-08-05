import Config

config :logger, level: :debug

config :bgp, BGP.MyServer,
  asn: 65_000,
  bgp_id: "172.16.1.3",
  connect_retry: [seconds: 5],
  port: 180,
  peers: [
    [
      asn: 65_001,
      bgp_id: "172.16.1.4",
      host: "172.16.1.4"
    ]
  ]
