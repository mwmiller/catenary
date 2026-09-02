defmodule Catenary.Live.PrefsManager do
  @moduledoc """
  LiveComponent for managing and displaying user preferences.
  """
  use Phoenix.LiveComponent
  alias Catenary.Display

  @impl true
  def update(assigns, socket) do
    {ac, lc, ec} = Catenary.clump_stats(assigns.clump_id)

    {:ok,
     assign(
       socket,
       Map.merge(assigns, %{
         blocked: blocked_map_set(assigns.clump_id),
         ac: ac,
         lc: lc,
         ec: ec,
         picked: "bg-slate-100 dark:bg-slate-800/50",
         unpicked: ""
       })
     )}
  end

  def option_value(i, selected_i) do
    selected = if i == selected_i, do: "selected", else: ""
    ~s(<option value="#{i}" #{selected}>#{i}</option>)
  end

  def radio_value(i, selected_i, name) do
    checked = if i == selected_i, do: "checked", else: ""

    ~s(<input class="accent-amber-500" type="radio" name="#{name}" value="#{i}" #{checked} />)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="preferences-view">
      <div id="identview-wrap" class="content-wrap">
        <div class="mx-auto flex max-w-3xl flex-col gap-4">
          <div class="rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-900 p-4">
            <div class="flex items-center gap-4">
              <a href={"/authors/" <> @identity} class="shrink-0">
                {Phoenix.HTML.raw(Display.scaled_avatar(@identity, 8, []))}
              </a>
              <div class="min-w-0 flex-1">
                <div class="text-sm text-slate-500 dark:text-slate-400">Active clump</div>
                <form method="post" id="clump-form" phx-change="clump-change" class="mt-1">
                  <label class="mr-1" for="clump_id">🎋</label>
                  <select
                    name="clump_id"
                    class="rounded-md border border-slate-300 dark:border-slate-600 bg-white dark:bg-slate-800 px-2 py-1 text-sm text-slate-900 dark:text-slate-100"
                  >
                    {for {c, _} <- @clumps, do: Phoenix.HTML.raw(option_value(c, @clump_id))}
                  </select>
                </form>
                <p class="mt-2 text-xs text-slate-500 dark:text-slate-400">
                  {@ec} log entries available across {@lc} logs from {@ac} authors in {@clump_id}.
                </p>
              </div>
            </div>
          </div>

          <div class="rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-900 p-4">
            <h2 class="mb-2 text-xs font-semibold uppercase tracking-wide text-slate-400 dark:text-slate-500">
              Identities
            </h2>
            <form method="post" id="identity-form" phx-change="identity-change">
              <div class="divide-y divide-slate-200 dark:divide-slate-700">
                <%= for {n, k} <- @identities do %>
                  <div class={"flex items-center gap-3 py-2 #{if k == @identity, do: @picked, else: @unpicked}"}>
                    <label
                      class="flex w-12 shrink-0 items-center gap-2 text-sm"
                      title="Use as identity"
                    >
                      {Phoenix.HTML.raw(radio_value(k, @identity, "selection"))}
                      {Phoenix.HTML.raw(
                        Display.scaled_avatar(k, 4, [
                          "block h-8 w-8 overflow-hidden rounded-full object-cover"
                        ])
                      )}
                    </label>
                    <input
                      class="w-40 rounded-md border border-slate-300 dark:border-slate-600 bg-white dark:bg-slate-800 px-2 py-1 text-sm text-slate-900 dark:text-slate-100"
                      type="text"
                      id={n}
                      value={n}
                      phx-blur={"rename-id-" <> n}
                    />
                    <span class="min-w-0 flex-1 truncate text-sm">{Phoenix.HTML.raw(
                      Display.linked_author(k, @aliases, :href)
                    )}</span>
                    <span class="shrink-0 text-xs text-slate-500 dark:text-slate-400">{Phoenix.HTML.raw(
                      log_info_string(@store, k)
                    )}</span>
                    <span class="flex w-8 shrink-0 items-center justify-center">
                      <a
                        href={"/export?whom=" <> URI.encode_www_form(n)}
                        download={n <> ".json"}
                        class="rounded px-1.5 py-0.5 text-slate-400 dark:text-slate-500 transition-colors hover:bg-amber-100 hover:text-amber-700 dark:hover:bg-amber-900/40 dark:hover:text-amber-400"
                        title="Export identity keys"
                      >⇤</a>
                    </span>
                    <span class="flex w-8 shrink-0 items-center justify-center">
                      <button
                        type="button"
                        class="rounded px-1.5 py-0.5 text-slate-400 dark:text-slate-500 transition-colors hover:bg-red-100 hover:text-red-700 dark:hover:bg-red-900/40 dark:hover:text-red-400"
                        value={n}
                        data-confirm={"Drop identity #{n}? This cannot be undone."}
                        phx-click="drop-id"
                        phx-value-name={n}
                      >⛒</button>
                    </span>
                  </div>
                <% end %>
              </div>
            </form>
            <form
              phx-submit="new-id"
              class="flex items-center gap-3 border-t border-slate-200 py-2 dark:border-slate-700"
            >
              <span class="flex w-12 shrink-0 items-center justify-start">
                <button
                  type="submit"
                  class="rounded-md border border-slate-300 dark:border-slate-600 px-1.5 text-sm text-slate-500 dark:text-slate-400 transition-colors hover:border-amber-500 hover:text-amber-600 dark:hover:border-amber-400 dark:hover:text-amber-400"
                  title="Create identity"
                >+</button>
              </span>
              <input
                class="w-40 rounded-md border border-dashed border-slate-300 dark:border-slate-600 bg-white dark:bg-slate-800 px-2 py-1 text-sm text-slate-500 dark:text-slate-400 placeholder:text-slate-400 dark:placeholder:text-slate-500"
                type="text"
                name="value"
                placeholder="new name"
                id="new-id"
                phx-blur="new-id"
              />
              <span class="min-w-0 flex-1 truncate text-xs text-slate-400 dark:text-slate-500">create and switch to</span>
              <span class="shrink-0 text-xs text-slate-400 dark:text-slate-500">none yet</span>
              <span class="flex w-8 shrink-0 items-center justify-center" />
            </form>
            <form
              method="post"
              action="/import"
              enctype="multipart/form-data"
              class="flex items-center gap-3 border-t border-slate-200 py-2 dark:border-slate-700"
            >
              <input type="hidden" name="_csrf_token" value={Phoenix.Controller.get_csrf_token()} />
              <span class="flex w-12 shrink-0 items-center justify-start">
                <button
                  type="submit"
                  class="rounded-md border border-slate-300 dark:border-slate-600 px-1.5 text-sm text-slate-500 dark:text-slate-400 transition-colors hover:border-amber-500 hover:text-amber-600 dark:hover:border-amber-400 dark:hover:text-amber-400"
                  title="Import identity"
                >⇥</button>
              </span>
              <label
                for="identity-file-input"
                class="w-40 shrink-0 cursor-pointer truncate rounded-md border border-slate-300 dark:border-slate-600 bg-white dark:bg-slate-800 px-2 py-1 text-sm text-slate-400 dark:text-slate-500 hover:border-amber-500 dark:hover:border-amber-400"
                id="identity-file-label"
                data-default="choose a .json file"
              >
                choose a .json file
              </label>
              <input
                id="identity-file-input"
                class="sr-only"
                type="file"
                name="identity_file"
                accept="application/json,.json"
                onchange="const l = document.getElementById('identity-file-label'); l.textContent = this.files[0] ? this.files[0].name : l.dataset.default; if (this.files[0]) { this.closest('form').submit(); }"
              />
              <span class="min-w-0 flex-1 truncate text-xs text-slate-400 dark:text-slate-500">import identity keys</span>
            </form>
            <div class="mt-3 flex items-center gap-2 border-t border-slate-200 dark:border-slate-700 pt-3">
              <label class="text-sm text-slate-600 dark:text-slate-300" for="facet_id">❖ Facet</label>
              <input
                class="w-16 rounded-md border border-slate-300 dark:border-slate-600 bg-white dark:bg-slate-800 px-2 py-1 text-sm text-slate-900 dark:text-slate-100"
                phx-blur="facet-change"
                type="numeric"
                name="facet_id"
                value={@facet_id}
              />
            </div>
          </div>

          <div class="rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-900 p-4">
            <h2 class="mb-2 text-xs font-semibold uppercase tracking-wide text-slate-400 dark:text-slate-500">
              Preferences
            </h2>
            <form method="post" id="pref-form" phx-change="prefs-change" class="flex flex-col gap-2">
              <label class="flex items-center gap-2 text-sm text-slate-700 dark:text-slate-300">
                <input
                  class="h-4 w-4 rounded border-slate-300 dark:border-slate-600 text-amber-500 dark:text-amber-400 focus:ring-1 focus:ring-amber-500/60 dark:focus:ring-amber-400/60"
                  type="checkbox"
                  name="automention"
                  checked={Catenary.Preferences.get(:automention)}
                /> Auto-mention
              </label>
              <label class="flex items-center gap-2 text-sm text-slate-700 dark:text-slate-300">
                <input
                  class="h-4 w-4 rounded border-slate-300 dark:border-slate-600 text-amber-500 dark:text-amber-400 focus:ring-1 focus:ring-amber-500/60 dark:focus:ring-amber-400/60"
                  type="checkbox"
                  name="autosync"
                  checked={Catenary.Preferences.get(:autosync)}
                /> Auto-sync
              </label>
            </form>
          </div>

          <div class="rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-900 p-4">
            <h2 class="mb-2 text-xs font-semibold uppercase tracking-wide text-slate-400 dark:text-slate-500">
              Accept log types
            </h2>
            <form method="post" id="accept-form" phx-submit="new-entry">
              <input type="hidden" name="log_id" value="1337" />
              <input type="hidden" name="listed" value="accept" />
              <div class="grid grid-cols-3 gap-1">
                <%= for {s, a} <- Display.all_pretty_log_pairs do %>
                  <label class="flex items-center gap-1.5 text-sm text-slate-700 dark:text-slate-300">
                    {log_accept_input(a, @blocked) |> Phoenix.HTML.raw()}&nbsp;{s}
                  </label>
                <% end %>
              </div>
              <div class="mt-3">{Phoenix.HTML.raw(Display.log_submit_button())}</div>
            </form>
          </div>

          <div class="rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-900 p-4">
            <h2 class="mb-2 text-xs font-semibold uppercase tracking-wide text-slate-400 dark:text-slate-500">
              Data maintenance
            </h2>
            <div class="flex flex-wrap gap-2">
              <button
                class="rounded-md border border-slate-300 dark:border-slate-600 px-3 py-1.5 text-sm text-slate-700 dark:text-slate-300 transition-colors hover:bg-slate-100 dark:hover:bg-slate-800"
                value="all"
                phx-disable-with="⌘⌘⌘"
                phx-click="shown"
              >
                catch up
              </button>
              <button
                class="rounded-md border border-slate-300 dark:border-slate-600 px-3 py-1.5 text-sm text-slate-700 dark:text-slate-300 transition-colors hover:bg-slate-100 dark:hover:bg-slate-800"
                value="none"
                phx-disable-with="⎚⎚⎚"
                phx-click="shown"
              >
                start fresh
              </button>
              <button
                class="rounded-md border border-slate-300 dark:border-slate-600 px-3 py-1.5 text-sm text-slate-700 dark:text-slate-300 transition-colors hover:bg-slate-100 dark:hover:bg-slate-800"
                value="all"
                phx-disable-with="〆〆〆"
                phx-click="compact"
              >
                compact logs
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp log_accept_input(:graph, _blocked),
    do: "☑︎ <input type=\"hidden\" name=\"log_name-graph\" value=\"graph\">"

  defp log_accept_input(name, blocked) do
    logs = QuaggaDef.logs_for_name(name) |> MapSet.new()
    # We'll assume that if any one is blocked we meant
    # to block them all.
    checked =
      case MapSet.intersection(blocked, logs) |> Enum.count() do
        0 -> " checked "
        _ -> ""
      end

    ln = Atom.to_string(name)

    ~s(<input class="h-4 w-4 rounded border-slate-300 dark:border-slate-600 text-amber-500 dark:text-amber-400 focus:ring-1 focus:ring-amber-500/60 dark:focus:ring-amber-400/60" type="checkbox"  name="log_name-) <>
      ln <> ~s(" value=") <> ln <> "\"" <> checked <> "/>"
  end

  defp blocked_map_set(clump_id) do
    clump_id |> Baobab.ClumpMeta.blocks_list() |> MapSet.new()
  end

  defp log_info_string(store, k) do
    logs = store |> Enum.filter(fn {a, _, _} -> a == k end)
    entries = logs |> Enum.reduce(0, fn {_, _, e}, a -> a + e end)

    humane_count(entries) <> " entries across " <> humane_count(logs) <> " logs"
  end

  defp humane_count(flt) when is_float(flt), do: humane_count(trunc(flt))
  defp humane_count(list) when is_list(list), do: humane_count(length(list))

  defp humane_count(str) when is_binary(str) do
    amt =
      try do
        String.to_integer(str)
      rescue
        _ -> String.length(str)
      end

    humane_count(amt)
  end

  defp humane_count(0), do: "no"
  defp humane_count(e) when e < 3, do: "a couple"
  defp humane_count(e) when e < 5, do: "a few"
  defp humane_count(e) when e < 10, do: "several"
  defp humane_count(e) when e < 144, do: "dozens of"
  defp humane_count(e) when e < 451, do: "hundreds of"
  defp humane_count(e) when is_integer(e), do: "very many"
  defp humane_count(_), do: "‽"
end
