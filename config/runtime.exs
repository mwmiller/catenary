import Config

config :catenary,
  application_dir: "~/.catenary",
  clumps: %{
    "Quagga" => [
      port: 0,
      announce: true,
      cryouts: [[mdns: []]]
    ]
  }
