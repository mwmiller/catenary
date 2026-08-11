# Catenary

A distributed, self-sovereign feed reader with an Elixir/Phoenix heart and a
native desktop shell. The UI is a Phoenix LiveView served from a locally bound
endpoint and rendered inside a [Tauri](https://tauri.app) webview.

## Quick start (dev server)

```
mise install        # pins elixir/erlang/rust/zig per .tool-versions
mix local.hex --force
mix deps.get
mix phx.server      # serves http://localhost:14041
```

Visit [`localhost:14041`](http://localhost:14041) in a browser.

## Desktop app

The native shell runs the Elixir backend as a Burrito-wrapped binary (spawned
as a Tauri sidecar) and draws the LiveView in the webview:

```
scripts/build-app.sh
```

This builds the backend release and the `catenary.app` shell. The shell's menu
bar has a **Dashboard** item (⌘D) that navigates the LiveView to
`/dashboard` (LiveDashboard), and native window resize events are reported
back so the app can remember its window size.

Development iteration of the shell alone, with `mix phx.server` already running:

```
cd src-tauri && cargo tauri dev
```

## Tests

```
mix test
```

## Release (self-contained backend)

```
MIX_ENV=prod mix release
```

Burrito wraps the release into a single executable under `burrito_out/`
(`catenary_macos`, `catenary_linux`, or `catenary.exe`). The desktop build
copies that artifact into `src-tauri/binaries/` for bundling.

## Learn more

  * Official website: https://www.phoenixframework.org/
  * Tauri docs: https://v2.tauri.app/
  * Source: https://github.com/phoenixframework/phoenix