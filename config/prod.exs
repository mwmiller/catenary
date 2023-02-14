import Config

config :catenary, CatenaryWeb.Endpoint,
  # Binding to loopback ipv4 address prevents access from other machines.
  # Change to `ip: {0, 0, 0, 0}` to allow access from other machines.
  http: [ip: {127, 0, 0, 1}, port: 14041],
  check_origin: false,
  secret_key_base: "5FLVVS9UwaB5UWAnrPIXBTk9eEJGr+vTvqOp742c1utBPSQxJUs6rFsmIklpCMT0"

config :catenary,
  application_dir: "~/.catenary"

# Do not print debug messages in production
config :logger, level: :error
