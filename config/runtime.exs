import Config

config :catenary,
  application_dir: "~/.catenary",
  facet_id: 0,
  clumps: %{
    "Quagga" => [fallback_node: [host: "quagga.nftease.online", port: 8483]],
    "Sesigo" => [fallback_node: [host: "10.1.2.12", port: 8483]]
  }
