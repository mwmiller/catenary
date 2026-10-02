# Build the dev app fixtures into priv/static so the browser has modules to
# load. The fixtures themselves live under test/support because they are
# scaffolding; this is only how they get a URL.
#
#   mix run --no-start scripts/make-app-fixture.exs

Code.require_file(Path.join([File.cwd!(), "test", "support", "app_fixture.ex"]))

for {module, name} <- [
      {Catenary.AppFixture, "app-fixture.wasm"},
      {Catenary.AppFixture.Refuser, "refuse-fixture.wasm"}
    ] do
  path = Path.join([File.cwd!(), "priv", "static", "assets", name])
  File.mkdir_p!(Path.dirname(path))
  File.write!(path, module.wasm())

  IO.puts("wrote #{path} (#{File.stat!(path).size} bytes)")
end
