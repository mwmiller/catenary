# Catenary

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

## What is it?

A peer-to-peer feed reader and publishing platform. Each user owns their
identity (a cryptographic keypair) and their content (signed, append-only
logs). There is no server, no account, and no third party that can censor
or revoke anything published.

## How it works

Catenary peers find each other and exchange data using a gossip protocol —
there is no central server coordinating anything. Once two nodes connect,
they each say what they have and what they want, and swap entries directly.

Each type of content (journal posts, replies, images, tags, game moves, etc.)
lives in its own append-only log, signed by its author. Because logs are
independent, each node can choose exactly which types of content to carry.
A node can follow someone's journal but not their game moves by blocking
that content type — the node simply won't store or relay it. Blocking works
by content type, by author, or by entire families of derived logs.

Multiple devices can share the same identity — a phone and a laptop each
write to their own slot within a content type. Other nodes see the combined
log as a single, coherent sequence.

## Quick start (dev server)

```
mise install        # pins elixir/erlang/rust/zig per .tool-versions
mix local.hex --force
mix deps.get
mix phx.server      # serves http://localhost:14041
```

## Desktop app

The native shell wraps the Elixir backend in a [Tauri](https://tauri.app)
webview. Build everything with:

```
scripts/build-app.sh           # full build (backend + shell)
cd src-tauri && cargo tauri dev # iterate on shell with mix phx.server running
```

## Install

Installers are on each [GitHub release](https://github.com/mwmiller/catenary/releases):

* **macOS** — `.dmg` (drag into Applications)
* **Windows** — `.exe` installer
* **Linux** — `.deb`, `.rpm`, or `.AppImage`

## Tests

```
mix test
```

## Release

```
scripts/build-app.sh           # backend + Tauri shell
MIX_ENV=prod mix release       # backend only
```

Backend binaries land in `burrito_out/`. The desktop build copies them
into `src-tauri/binaries/` for bundling.
