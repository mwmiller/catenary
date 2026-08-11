#!/usr/bin/env bash
# Builds the full native desktop app.
#
# It produces two things:
#   * The Elixir backend as a self-contained Burrito binary (burrito_out/)
#   * The Tauri shell binary (src-tauri/target/release/catenary)
#
# The Tauri shell spawns the Burrito binary as a sidecar at runtime, so the
# sidecar must sit next to the shell binary (Tauri resolves it relative to its
# own location). We copy it into both Tauri's expected source location and the
# build output directory.
#
set -euo pipefail
cd "$(dirname "$0")/.."

# Pin tools per .tool-versions via `mise`. If mise is not used, the tools
# (elixir/erlang, rust, zig, xz) must already be on PATH.
if command -v mise >/dev/null 2>&1; then
  eval "$(mise env 2>/dev/null || true)"
fi

# --- Elixir backend ----------------------------------------------------------#
mix local.hex --force
mix deps.get
mix deps.unlock --unused
mix compile --warnings-as-errors
mix test
mix assets.deploy

# Burrito targets only the build host for a faster, local-only backend.
case "$(uname -s)" in
  Darwin)  burrito_target=macos ;;
  Linux)   burrito_target=linux ;;
  MINGW*|MSYS*|CYGWIN*) burrito_target=windows ;;
  *) echo "unsupported build host" >&2; exit 1 ;;
esac
MIX_ENV=prod BURRITO_TARGET="$burrito_target" mix release --overwrite

backend_artifact=""
for cand in \
  "burrito_out/catenary_macos" \
  "burrito_out/catenary_linux" \
  "burrito_out/catenary_windows.exe" \
  "burrito_out/catenary.exe"; do
  if [ -f "$cand" ]; then
    backend_artifact="$cand"; break
  fi
done
if [ -z "$backend_artifact" ]; then
  echo "expected a burrito_out/catenary_* artifact, none found" >&2
  exit 1
fi

# --- Native shell + sidecar wiring -------------------------------------------#
triple="$(rustc -vV | sed -n 's/^host: //p')"

# (1) Source location Tauri validates at compile time (triples-suffixed name).
mkdir -p src-tauri/binaries
cp -f "$backend_artifact" "src-tauri/binaries/catenary-backend-${triple}"
chmod +x "src-tauri/binaries/catenary-backend-${triple}"

cargo_release_bin="src-tauri/target/release/catenary"
if [ -x "$cargo_release_bin" ]; then
  # (2) Runtime location: Tauri resolves the sidecar next to the shell binary.
  mkdir -p src-tauri/target/release/binaries
  cp -f "$backend_artifact" src-tauri/target/release/binaries/catenary-backend
  chmod +x src-tauri/target/release/binaries/catenary-backend
else
  # Build the shell (this is where tauri-build also validates the sidecar above).
  ( cd src-tauri && cargo build --release )
  mkdir -p src-tauri/target/release/binaries
  cp -f "$backend_artifact" src-tauri/target/release/binaries/catenary-backend
  chmod +x src-tauri/target/release/binaries/catenary-backend
fi

echo
echo "Built the desktop app."
echo "  backend:  $backend_artifact"
echo "  shell:    $cargo_release_bin"
echo
echo "Run it with:  ./$cargo_release_bin"
echo "Or bundle it into a proper .app via:  npx @tauri-apps/cli build"