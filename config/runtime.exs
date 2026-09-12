import Config

if config_env() != :test do
  config :catenary,
    application_dir: "~/.catenary",
    clumps: %{
      "Quagga" => [
        port: 0,
        announce: true,
        cryouts: [[mdns: []]]
      ],
      # Offline dev/test clump: not announced and no cryouts, so nothing
      # syncs with it. Add an oasis connection manually to sync.
      "Dev" => [
        port: 0,
        announce: false,
        cryouts: []
      ]
    }
end
