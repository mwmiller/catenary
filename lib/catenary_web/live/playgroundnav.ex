defmodule Catenary.Live.PlaygroundNav do
  @moduledoc """
  LiveComponent rendering the playground's right rail.

  The rail sits where `Catenary.Live.Navigation` puts its compose and challenge
  triggers on a feed screen. This is an authoring workspace rather than
  somewhere to post from, so those triggers do not apply and `Navigation` is
  simply not drawn while the playground is on screen — nothing about it is
  frozen or thrown away. The history stacks, the open compose panel and the
  current entry all live on the parent LiveView and are read (never owned) by
  `Navigation`, so the component draws again untouched when the author leaves
  the playground.

  What belongs here is commands acting on whatever is in the editor: Run and
  Stop for the buffer, then replay, the store fixture picker and the publish
  panel — plus ⇥, which takes a foreign `.wasm` straight to the pane without
  the buffer ever being involved. ⇥ is the glyph
  `Catenary.Live.PrefsManager` already uses for bringing a file in from disk
  (⇤ is its export), so this reads as an import rather than a download. What
  gets *walked* rather than run — a trace, a version — is the left rail's job,
  `Catenary.Live.PlaygroundTimeline`. Neither rail is ever given a disabled
  stand-in for a tool that does not exist yet: a button that cannot be pressed
  would be a lie about the state of the build.

  None of these controls publishes, so none is amber — amber is reserved for
  actions that actually write to a log.
  """
  use Phoenix.LiveComponent

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-w-full w-56 flex flex-col items-center">
      <div class="flex items-center gap-1 text-xl px-2 py-2">
        <button
          type="button"
          phx-click="playground-run"
          phx-target={@myself}
          title="Run"
          aria-label="Run — compile the buffer and start it"
          class="btn-icon"
        >▶</button>
        <button
          type="button"
          phx-click="playground-stop"
          phx-target={@myself}
          title="Stop"
          aria-label="Stop — terminate the running module"
          class="btn-icon"
        >■</button>
        <%!-- The picker is a file input behind a glyph. ⇥ is what Preferences
             already uses for an import, so the English lives in the label's
             tooltip and in the input's own name; the hook reads the file and
             hands it to the run pane, which is where instantiating it
             happens. --%>
        <label
          id="wasm-dropin"
          phx-hook="WasmDropin"
          title="Import a .wasm file"
          class="btn-icon cursor-pointer"
        >
          ⇥
          <input
            type="file"
            accept=".wasm,application/wasm"
            aria-label="Import a .wasm file into the run pane"
            class="sr-only"
          />
        </label>
      </div>
    </div>
    """
  end

  # The rail is a component, but the run is not its to perform: compiling and
  # pushing the module belongs to the LiveView that holds the draft, and the
  # components all share its process, so this is a message rather than a
  # callback with a target.
  @impl true
  def handle_event("playground-run", _params, socket) do
    send(self(), :playground_run)
    {:noreply, socket}
  end

  def handle_event("playground-stop", _params, socket) do
    send(self(), :playground_stop)
    {:noreply, socket}
  end
end
