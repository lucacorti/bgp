import Config

config :logger, level: :debug

config :bgp, BGP.MyServer,
  asn: 65_000,
  bgp_id: "192.168.64.1",
  peers: [
    [asn: 65_001, bgp_id: "192.168.64.2", connect_retry: [secs: 5], host: "192.168.64.2"]
  ]
