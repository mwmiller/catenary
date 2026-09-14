import Config

if config_env() != :test do
  config :catenary,
    application_dir: System.get_env("CATENARY_HOME", "~/.catenary"),
    # Fallback clumps when no clumps.toml is present (see Catenary.Config).
    clumps: %{
      "Quagga" => [
        port: 0,
        announce: true,
        cryouts: [[mdns: []]]
      ]
    }
end
