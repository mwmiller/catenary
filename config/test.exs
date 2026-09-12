import Config

# Tests must be hermetic: never read or write the user's real ~/.catenary.
# Persisted view/entry preferences would otherwise select which render/1
# clause mounts "/" with, breaking tests that assume the default view.
config :catenary,
  application_dir: Path.expand("~/.catenary-test"),
  clumps: %{
    "Dev" => [
      port: 0,
      announce: false,
      cryouts: []
    ]
  }

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :catenary, CatenaryWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "SPxKtYJrt9CsLLapQ3vv2Lzr5P2AvjZnbbdCMMWfxW6Y5g1OBpeLJs29iveA6CrC",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime
