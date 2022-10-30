import Config

config :catenary,
  application_dir: "~/.catenary",
  clumps: %{
    "Quagga" => [port: 8483, fallback_node: [host: "quagga.zebrine.net", port: 8483]],
    "Pitcairn" => [port: 8485, fallback_node: [host: "sally.zebrine.net", port: 8485]]
  }
