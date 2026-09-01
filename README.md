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
bar has a **Go** menu with keyboard shortcuts for quick navigation:

| Item | Shortcut | View |
|------|----------|------|
| Dashboard | ⌘D | LiveDashboard |
| Preferences | ⌘, | Settings |
| Oases | ⌘O | Peers/Nodes |

Native window resize events are reported back so the app can remember its
window size. Choosing **Quit Catenary** terminates the backend and releases
its port.

## Install (end users)

Ready-made installers are attached to each [GitHub release](https://github.com/mwmiller/catenary/releases):

* **macOS** — `Catenary-<version>-macos-aarch64.dmg`: open it and drag Catenary
  into Applications. (A `.zip` fallback is also provided.)
* **Windows** — `Catenary-<version>-windows-x86_64-setup.exe`: run the
  installer; it adds Start-menu shortcuts and an uninstaller.
* **Linux**
  * Debian / Ubuntu / Pop!_OS: `sudo apt install ./Catenary-<version>-linux-x86_64.deb`
  * Fedora / RHEL / openSUSE: `sudo dnf install ./Catenary-<version>-linux-x86_64.rpm`
  * Any other distro: download the `.AppImage`, make it executable
    (`chmod +x`, requires `libwebkit2gtk-4.1-0`), and run it.

Development iteration of the shell alone, with `mix phx.server` already running:

```
cd src-tauri && cargo tauri dev
```

## Connecting to peers

The **Peers** view (⇆ in the navigation bar) is the Oasis Explorer:

* **Announced oases (◉)** — recently announced oases are listed with their
  operator and clump identity. Click a row's **⇆** to connect; a green **⥀**
  marks an established connection. A muted **⥀** means a sync is being
  attempted.
* **Manual connect (⌖)** — enter a peer's host and port in the separate
  fields (pre-filled with the clump's bootstrap node) and click **⇆**. The
  entered peer is tracked below the form: pulsing **↯** while connecting,
  green **⥀** once connected, and **⛒** if the connection could not be
  established within 20 seconds. Malformed targets (empty host, non-numeric
  or out-of-range port) are ignored with a warning in the log. Both IPv4 and
  IPv6 peers are supported.

Status indicators are glyphs throughout; hover them for tooltips.

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