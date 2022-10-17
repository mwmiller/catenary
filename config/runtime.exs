import Config

config :catenary,
  application_dir: "~/.catenary",
  clumps: %{
    "Quagga" => [fallback_node: [host: "quagga.nftease.online", port: 8483]],
    "Pitcairn" => [fallback_node: [host: "sally.nftease.online", port: 8485]]
  }
