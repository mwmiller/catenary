#!/usr/bin/env bash
# Rebuilds assets/vendor/codemirror.mjs, the vendored CodeMirror 6 bundle.
#
# This project has no package.json and its normal builds are npm-free: esbuild
# resolves `phoenix` and friends through NODE_PATH=deps, and assets/vendor holds
# committed third-party code (topbar.js). The editor follows that rule rather
# than adding an npm install to every build, so the bundle is committed instead
# of fetched, and nothing at runtime touches the network.
#
# Run it only to upgrade the editor:
#
#   ./scripts/build-codemirror.sh
#
# It needs network access for that one run, installs into a temporary
# directory, and removes it on exit.
set -euo pipefail
cd "$(dirname "$0")/.."

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# esbuild is pinned to the version config/config.exs runs the app's own bundle
# with, so the vendored file is transpiled to the same target.
cat > "$work/package.json" <<'JSON'
{
  "private": true,
  "type": "module",
  "dependencies": {
    "codemirror": "^6.0.0",
    "@codemirror/language": "^6.0.0",
    "@codemirror/lint": "^6.0.0",
    "@codemirror/state": "^6.0.0",
    "@codemirror/view": "^6.0.0",
    "@lezer/highlight": "^1.0.0"
  },
  "devDependencies": {
    "esbuild": "0.25.9"
  }
}
JSON

# What the playground needs today, plus the pieces the DSL compiler will drive
# once it lands: diagnostics for source-position errors, and the language /
# highlighting scaffolding for a real syntax mode. Types are dropped because
# esbuild is bundling JavaScript and the packages publish no declarations here.
cat > "$work/entry.js" <<'JS'
export { basicSetup, minimalSetup } from "codemirror"
export {
  Decoration,
  EditorView,
  ViewPlugin,
  keymap,
  placeholder,
} from "@codemirror/view"
export {
  Compartment,
  EditorState,
  StateEffect,
  StateField,
} from "@codemirror/state"
export { linter, lintGutter, setDiagnostics } from "@codemirror/lint"
export {
  HighlightStyle,
  LanguageSupport,
  StreamLanguage,
  syntaxHighlighting,
} from "@codemirror/language"
export { tags } from "@lezer/highlight"
JS

echo "installing editor packages..."
npm install --prefix "$work" --no-audit --no-fund --loglevel=error

"$work/node_modules/.bin/esbuild" "$work/entry.js" \
  --bundle \
  --format=esm \
  --minify \
  --target=es2016 \
  --outfile=assets/vendor/codemirror.mjs

echo
echo "resolved:"
npm ls --prefix "$work" --depth=0 2>/dev/null | sed 's/^/  /'
echo
ls -lh assets/vendor/codemirror.mjs | awk '{print "wrote assets/vendor/codemirror.mjs (" $5 ")"}'
