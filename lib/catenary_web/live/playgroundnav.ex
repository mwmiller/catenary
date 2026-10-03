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

  The publish trigger only opens the panel, so it is not amber; the panel's
  own submit is, because that is the button that writes. Amber is reserved
  for actions that actually write to a log. What gets written is the buffer
  as it stands — compile, artifact, source, manifest, listing — decided here
  only in the sense that this is where the words are typed: the run, the
  caps and the appends all belong to the LiveView that holds the draft and
  to `Catenary.LogWriter`, the one place every write to a log goes through.
  The gate a run is judged by (`_gate`, `_gateVerdict`) is the pane's
  business and is not consulted to publish: §5 decision #21 keeps that
  decision with whoever is watching the app, not with the editor.
  """
  use Phoenix.LiveComponent

  import Catenary.UI, only: [panel_cls: 0, input_cls: 0, label_cls: 0, help_cls: 0]

  @impl true
  def update(assigns, socket) do
    # The open/closed state is this component's own — the parent is told
    # what to publish, never which panel is showing.
    {:ok, socket |> assign(assigns) |> assign_new(:publish, fn -> false end)}
  end

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
        <button
          type="button"
          phx-click="toggle-publish"
          phx-target={@myself}
          aria-expanded={to_string(@publish)}
          aria-controls="publish-panel"
          title="Publish"
          aria-label="Publish — open the panel that writes this buffer to the logs"
          class="btn-icon"
        >⇪</button>
      </div>
      <div :if={@publish} class="w-full flex justify-end px-2">
        <button
          type="button"
          phx-click="toggle-publish"
          phx-target={@myself}
          title="Close panel"
          aria-label="Close panel"
          class="btn-ghost"
        >⍟</button>
      </div>
      <div :if={@publish} id="publish-panel" class="w-full flex justify-center px-2 mt-1">
        <form
          id="publish-form"
          phx-submit="publish-app"
          phx-target={@myself}
          class={panel_cls() <> " w-full"}
        >
          <div class="mb-2">
            <label for="publish-slug" class={label_cls()}>Slug</label>
            <input
              id="publish-slug"
              name="slug"
              type="text"
              required
              autocomplete="off"
              spellcheck="false"
              placeholder="hello-app"
              class={input_cls()}
            />
          </div>
          <div class="mb-2">
            <label for="publish-title" class={label_cls()}>Title</label>
            <input
              id="publish-title"
              name="title"
              type="text"
              autocomplete="off"
              spellcheck="false"
              placeholder="optional"
              class={input_cls()}
            />
          </div>
          <div class="mb-2">
            <label for="publish-description" class={label_cls()}>Description</label>
            <textarea
              id="publish-description"
              name="description"
              rows="2"
              placeholder="optional"
              class={input_cls()}
            ></textarea>
          </div>
          <div class="mb-2">
            <label for="publish-version" class={label_cls()}>Version</label>
            <input
              id="publish-version"
              name="version"
              type="text"
              autocomplete="off"
              spellcheck="false"
              value="0.1.0"
              class={input_cls()}
            />
          </div>
          <p class={help_cls()}>
            Compiles the buffer as it stands, then writes the artifact, its
            source, a manifest and a listing to your logs.
          </p>
          <button
            type="submit"
            class="btn-primary w-full mt-2"
            aria-label="Publish — writes a listing to the log"
          >Publish</button>
        </form>
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

  def handle_event("toggle-publish", _params, socket) do
    {:noreply, assign(socket, publish: not socket.assigns.publish)}
  end

  # The form's own words, plus nothing: the buffer the words apply to is the
  # LiveView's assign, which merges it in and hands the lot to the writer.
  def handle_event("publish-app", params, socket) do
    send(self(), {:playground_publish, params})
    {:noreply, assign(socket, publish: false)}
  end
end
