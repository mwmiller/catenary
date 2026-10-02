defmodule Catenary.Live.AppViewer do
  @moduledoc """
  LiveComponent hosting a single running app.

  The component owns exactly two things: which listing is running, and the
  host operations that listing asks for. The app context — clump, publisher
  and slug — is assembled here from the entry the parent navigated to, so a
  worker can never name a different scope for itself: every `app-want` is
  answered against this fixed context, built server-side.

  Drawing the app is the `AppRunner` hook's job, mounted on the pane and
  left alone by `phx-update="ignore"` so LiveView's patches do not overwrite
  what it wrote. This component supplies the frame and the two sinks — a
  print log and a rendered view — that the hook fills in.
  """
  use CatenaryWeb, :live_component

  alias Catenary.{AppHost, AppWire, Display}

  @impl true
  def update(%{clump_id: clump_id, pk: pk, slug: slug} = assigns, socket) do
    app = AppHost.app(clump_id, pk, slug)
    {:ok, assign(socket, Map.put(assigns, :app, app))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="app-explore-wrap" class="content-wrap">
      <div class="flex flex-col gap-4">
        <div class="flex flex-col gap-1">
          <div class="flex items-center gap-2 min-w-0">
            <span class="px-1.5 py-0.5 rounded text-[10px] font-bold uppercase bg-purple-500 text-white">app</span>
            <h1 class="text-lg font-semibold font-mono truncate text-slate-800 dark:text-slate-100">
              {@slug}
            </h1>
          </div>
          <div class="flex items-center gap-1.5 text-xs text-slate-500 dark:text-slate-400 min-w-0">
            <span class="shrink-0">published by</span>
            {Display.scaled_avatar(@pk, 2) |> Phoenix.HTML.raw()}
            {Display.linked_author(@pk, @aliases) |> Phoenix.HTML.raw()}
          </div>
        </div>

        <div
          id={pane_id(@pk, @slug)}
          phx-hook="AppRunner"
          phx-update="ignore"
          phx-target={@myself}
          data-worker-src={~p"/assets/app_worker.js"}
          data-wasm-src={wasm_src(@slug)}
          class="rounded-lg border border-slate-200 dark:border-slate-700 p-3 flex flex-col gap-2"
        >
          <p id="app-status" class="text-sm text-slate-400 dark:text-slate-600">
            No module loaded.
          </p>
          <pre
            id="app-print"
            class="hidden whitespace-pre-wrap text-xs font-mono text-slate-600 dark:text-slate-300"
          ></pre>
          <div
            id="app-view"
            class="hidden whitespace-pre-wrap text-sm font-mono text-slate-700 dark:text-slate-200"
          >
          </div>
        </div>
      </div>
    </div>
    """
  end

  # The reply goes back to whichever hook made the call, so one round trip is
  # one promise resolution: the worker never has to correlate an id by hand.
  @impl true
  def handle_event("app-want", %{"op" => op, "args" => args}, socket) do
    {:reply, AppWire.request(socket.assigns.app, op, args), socket}
  end

  def handle_event("app-want", _params, socket) do
    {:reply, AppWire.request(socket.assigns.app, nil, nil), socket}
  end

  # The pane is ignored by LiveView, so it is never patched — only replaced.
  # Naming it after the app is what makes a second app get a fresh pane (and
  # a fresh hook, with the previous app's print log gone) instead of the
  # first app's leftovers.
  defp pane_id(pk, slug), do: "app-pane-#{pk}-#{slug}"

  # Where the module comes from. A listing's manifest will name its own
  # artifact; until it does, a slug can be pointed at a module in the dev
  # config so the harness has something to run.
  defp wasm_src(slug) do
    :catenary
    |> Application.get_env(:app_wasm, %{})
    |> Map.get(slug)
  end
end
