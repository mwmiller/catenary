# Developing Catenary

Catenary is an Elixir/Phoenix backend with a [Tauri](https://tauri.app)
desktop shell. The backend owns identity, content, and the mesh; the shell is
a webview that talks to it over loopback.

For what the software *is* and how to install it, see [README.md](README.md).

## Toolchain

Versions are pinned in `.tool-versions` and installed by [mise](https://mise.jdx.dev):

```
mise install
```

That covers Elixir 1.20.3/OTP 29, Erlang 29.0.5, Rust 1.98.1, Zig 0.16.0, and
Node 26.8.1. Rust and Zig are only needed for the desktop shell.

The mesh protocol is **Bushbaby**, which is a separate repository developed in
a sibling checkout alongside Catenary. Catenary consumes it as the `:baby`
Hex dependency at the version in `mix.exs`, so you do not need the sibling
checkout to build or run this project — you only need it if you are working
on the protocol itself.

## Running the backend

```
mix local.hex --force
mix deps.get
mix phx.server
```

Serves <http://localhost:14041>, bound to loopback. The desktop shell expects
this port, so keep it running when iterating on the shell.

## Running the desktop shell

```
scripts/build-app.sh             # full build: backend binaries + Tauri shell
cd src-tauri && cargo tauri dev # iterate on the shell, with mix phx.server up
```

`scripts/build-app.sh` builds the backend with Burrito, then copies the
binaries into `src-tauri/binaries/` for bundling. Raw backend binaries land in
`burrito_out/`.

Static assets are generated and gitignored, so rebuild them after changing
anything in `assets/`:

```
mix assets.deploy
```

## Tests and checks

```
mix precommit   # format check, credo --strict, warnings-as-errors, tests
mix test
```

`mix precommit` is the same set of checks CI runs on a release build, plus
`mix test` for the fast loop. The release workflow itself runs only
`compile`, `test`, and `assets.deploy` — it does not run `precommit`, so run
it locally before tagging.

## Versions

The version is repeated in four places, and they are expected to match:

| File | Key |
| --- | --- |
| `mix.exs` | `:version` |
| `src-tauri/tauri.conf.json` | `version` |
| `src-tauri/Cargo.toml` | `version` |
| `src-tauri/Cargo.lock` | the `catenary` package entry |

Rather than editing those by hand, use the task:

```
mix version.set 0.194.0   # set all four to an exact version
mix version.set --next    # advance to the next prime minor
mix version.set --check   # report each and fail if they disagree
```

Minor versions are kept to prime numbers. `--check` exits nonzero on drift,
and `mix precommit` catches drift independently via
`test/catenary/version_test.exs`.

`Cargo.toml` is written directly rather than derived. Cargo has no include
mechanism for a manifest field, and Tauri resolves a `package.json` version
path against the process working directory rather than the config file's
directory, so neither is safe to build a release on.

## Releasing

Releases are tag-triggered. Push a `v*` tag and
[`.github/workflows/build.yml`](.github/workflows/build.yml) builds the
backend for all three platforms, bundles the desktop app, and publishes
installers to the release.

```
git tag v0.194.0
git push origin main --tags
```

The tag must match the version in `src-tauri/tauri.conf.json`, so set it with
`mix version.set` first and commit that. macOS artifacts are signed only if
the signing secrets are present in the repository; without them the build
succeeds and produces unsigned output.

To produce the artifacts locally instead:

```
scripts/build-app.sh           # backend + Tauri shell
MIX_ENV=prod mix release       # backend only
```
