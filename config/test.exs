import Config

# Tests must be hermetic: never read or write the user's real ~/.catenary.
# Persisted view/entry preferences would otherwise select which render/1
# clause mounts "/" with, breaking tests that assume the default view.
config :catenary,
  application_dir: Path.expand("~/.catenary-test"),
  # Suites drive the host far faster than any run could — one file may
  # hammer a single app in a tight loop for a whole test — so the
  # per-app call budget is off here. `Catenary.AppRateTest` turns it back
  # on around its own assertions.
  app_rate_burst: :infinity,
  # The publish debounce counts wall-clock milliseconds, and a CI runner can
  # take longer than the two-second double-click window between two renders of
  # the same test. Widening it costs nothing here: the fingerprint lives in
  # LiveView socket state and every test mounts its own.
  publish_debounce_ms: 300_000,
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
