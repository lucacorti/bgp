import Config

config :logger, level: :debug

config :bgp, BGP.TestServerA,
  asn: 64_496,
  bgp_id: "172.16.1.3",
  networks: ["12.12.0.0/20"],
  port: 60_179,
  peers: [
    [
      asn: 65_536,
      connect_retry: [seconds: 5],
      bgp_id: "172.16.1.4",
      host: "127.0.0.1"
    ]
  ]

config :bgp, BGP.TestServerB,
  asn: 65_536,
  bgp_id: "172.16.1.4",
  networks: ["13.12.0.0/20"],
  port: 60_180,
  peers: [
    [
      asn: 64_496,
      connect_retry: [seconds: 5],
      bgp_id: "172.16.1.3",
      host: "127.0.0.1"
    ]
  ]
