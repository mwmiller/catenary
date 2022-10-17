import Config

config :catenary,
  application_dir: "~/.catenary",
  clumps: %{
    "Quagga" => [port: 8483, fallback_node: [host: "quagga.nftease.online", port: 8483]],
    "Pitcairn" => [port: 8485, fallback_node: [host: "sally.nftease.online", port: 8485]]
  }
