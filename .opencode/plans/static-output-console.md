# Static-size output console + step-7 groundwork

## Problem
The starter's `on ui` prints "tapped" on every pointer down/move/up; `#app-print`
is an unbounded `<pre>` in a `flex flex-col` pane, so a touch flood grows the
pane and warps the layout. Touching the canvas edge counts as a `ui` event
(apps own hit-testing), so the flood is expected behavior — the console must
not let it move the interface.

## Fix
1. `lib/catenary_web/live/appplayground.ex` + `lib/catenary_web/live/appviewer.ex`
   — give `#app-print` a static height and its own scroll region (`h-32
   overflow-y-auto`, keep mono/text-xs colors); always rendered (no `hidden`
   toggle) so size never shifts.
2. `assets/js/app_runner.js` — after appending text, scroll the console to the
   bottom (`scrollTop = scrollHeight`); drop the `classList.remove("hidden")`
   lines that no longer apply.
3. `mix esbuild default`, browser-verify (touch canvas repeatedly → console
   scrolls, view/canvas stay put, no warp), run tests, `mix precommit`, commit.

## Also in this pass
- Plan doc: amend decision #17 → source entry holds **WAT only** (DSL never stored).

## Deferred (ask before starting)
Step 7 publish pipeline: fixture scope, size-cap value, host `publish` effect vs
panel priority.
