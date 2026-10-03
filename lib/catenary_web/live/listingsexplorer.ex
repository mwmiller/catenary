defmodule Catenary.Live.ListingsExplorer do
  @moduledoc """
  LiveComponent rendering the listings index.

  Reads the `:listings` index table and shows every `(pk, slug)` the control
  log currently announces — today app listings, and anything else that lands
  on the log once a second family is announced. Each row carries the
  release's words and the hash its bytes must have; the bytes themselves
  live in the family's artifact kind log and are only fetched when a viewer
  opens the entry, so this view answers "what exists" and nothing else.

  Rows belonging to a family the viewer has blocked are dropped rather than
  greyed, the way the challenge explorer keeps blocked games out of its
  lists. With only `:app` announced today that is all-or-nothing, but the
  check is written against the row's own tag so a second family on the
  `:listing` control log arrives already filtered.

  The header also carries the **New app** action. That is navigation out of
  this view rather than a listing — it opens the playground on an empty
  draft — and it is where listing filter and sort controls will sit when
  they arrive, beside it rather than replacing it.
  """
  use Phoenix.LiveComponent
  alias Catenary.Display

  @impl true
  def update(assigns, socket) do
    {:ok, assign(socket, %{listings: listings(), aliases: Map.get(assigns, :aliases, [])})}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="listings-explore-wrap" class="content-wrap">
      <div class="flex flex-col gap-4">
        <div class="flex items-center justify-between gap-2">
          <h1 class="text-lg font-semibold text-slate-800 dark:text-slate-100">Listings Explorer</h1>
          <div class="flex shrink-0 items-center gap-3">
            <span :if={@listings != []} class="text-xs text-slate-400 dark:text-slate-500">
              {@listings |> length() |> pluralize("listing", "listings")}
            </span>
            <button
              :if={Catenary.Preferences.accept_log_name?(:listing)}
              type="button"
              phx-click="new-playground"
              phx-target={@myself}
              title="New app"
              aria-label="New app — open the playground"
              class="btn-ghost"
            >+</button>
          </div>
        </div>

        <%= if @listings == [] do %>
          <p class="text-slate-400 dark:text-slate-600 text-sm">No listings.</p>
        <% else %>
          <div class="flex flex-col gap-2">
            <%= for row <- @listings do %>
              <%!-- The row is a card with two actions, never one button
                  inside another: nested buttons are invalid HTML, and the
                  parser closes the outer one early, which used to throw the
                  author out of its row and drag the third column out of the
                  layout. Opening the app is the left branch, going to the
                  author the right one, so they cannot nest. --%>
              <div class="flex items-stretch gap-2 rounded-lg border border-slate-200 dark:border-slate-700 p-2 hover:border-amber-500 dark:hover:border-amber-400 transition-colors">
                <button
                  type="button"
                  phx-click="open-app"
                  phx-target={@myself}
                  phx-value-pk={row.pk}
                  phx-value-slug={row.slug}
                  class="min-w-0 flex-1 text-left flex flex-col gap-1"
                >
                  <span class="flex min-w-0 items-center gap-2">
                    {family_badge(row.family) |> Phoenix.HTML.raw()}
                    <span class="truncate font-mono text-sm text-slate-800 dark:text-slate-100">{row.slug}</span>
                    <span class="rounded bg-slate-200 px-1.5 py-0.5 text-[10px] font-bold text-slate-700 dark:bg-slate-700 dark:text-slate-300">v{row.version}</span>
                  </span>
                  <span class="block truncate text-xs text-slate-500 dark:text-slate-400">{description_text(
                    row
                  )}</span>
                </button>
                <%!-- The right-hand column is as tall as the card, so the
                    author sits on the name line and the date drops to the
                    description's line, both flush to the same right edge.
                    Stacked here rather than in the button, which is the
                    action to open the app. --%>
                <div class="flex shrink-0 flex-col items-end justify-between text-xs text-slate-500 dark:text-slate-400">
                  <div class="flex items-center gap-1.5">
                    {Display.scaled_avatar(row.pk, 2) |> Phoenix.HTML.raw()}
                    {Display.linked_author(row.pk, @aliases) |> Phoenix.HTML.raw()}
                  </div>
                  <span>{published_day(row)}</span>
                </div>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # Opening a listing is navigation, and navigation belongs to the parent
  # LiveView. Components run in that process, so a message shaped like the
  # one the parent already handles is the whole hand-off.
  #
  # The row is looked up again rather than trusted: the click payload comes
  # from the client, and only a `(pk, slug)` the control log actually
  # announces should be openable.
  @impl true
  def handle_event("open-app", %{"pk" => pk, "slug" => slug}, socket) do
    if listed?(pk, slug) do
      send(self(), %{view: :app, entry: {:app, {pk, slug}}})
    end

    {:noreply, socket}
  end

  # Authoring is navigation like opening a listing is: the blank draft is the
  # `:all` entry, and the parent's `handle_info` carries it onto the back stack
  # the same way. The button is already hidden without the listing log, but the
  # gate is repeated because the message rather than the button is what opens
  # the view, and a playground with no log to publish to is a dead end.
  def handle_event("new-playground", _, socket) do
    if Catenary.Preferences.accept_log_name?(:listing) do
      send(self(), %{view: :playground, entry: :all})
    end

    {:noreply, socket}
  end

  defp listed?(pk, slug) when is_binary(pk) and is_binary(slug) do
    :ets.lookup(:listings, {pk, slug}) != []
  rescue
    ArgumentError -> false
  end

  defp listed?(_pk, _slug), do: false

  # Read defensively: the endpoint starts ahead of the index workers, so a
  # first paint can beat the `:listings` table into existence.
  defp listings do
    clump_id = Catenary.Preferences.get(:clump_id)

    case :ets.lookup(:listings, :display) do
      [{:display, rows}] -> Enum.reject(rows, &blocked?(&1, clump_id))
      _ -> []
    end
  rescue
    ArgumentError -> []
  end

  defp blocked?(%{family: tag}, clump_id)
       when is_integer(tag) and tag >= 1 and tag <= 255,
       do: Catenary.BlockLog.blocked_family?(tag, clump_id)

  defp blocked?(_row, _clump_id), do: false

  # The listing's own words, for the left of the second line. The control
  # log is written by anyone, so the text is foreshortened here instead of
  # being trusted to be short: the span ellipsizes it to one line, and the
  # slice keeps a huge one out of the explorer's DOM.
  defp description_text(%{description: text}) when is_binary(text) and text != "",
    do: String.slice(text, 0, 160)

  defp description_text(_row), do: ""

  # The day it was listed, for the right of that line. Both shapes a writer
  # may use — `DateTime.to_string/1` and ISO 8601 — lead with the date, and
  # it is what a sort or a filter will key on, so it is shown for every row
  # rather than only the ones without a description. A field nobody wrote,
  # or one that is not text at all, leaves the span empty and the row
  # renders anyway.
  @date_prefix ~r/^\d{4}-\d{2}-\d{2}/

  defp published_day(%{published: published}) when is_binary(published) do
    case Regex.run(@date_prefix, published) do
      [day] -> day
      _ -> ""
    end
  end

  defp published_day(_row), do: ""

  defp family_badge(tag) when is_integer(tag) do
    label =
      case QuaggaDef.family_name(tag) do
        :unknown -> "family #{tag}"
        name -> Atom.to_string(name)
      end

    "<span class=\"px-1.5 py-0.5 rounded text-[10px] font-bold uppercase bg-purple-500 text-white\">" <>
      label <> "</span>"
  end

  defp pluralize(1, one, _many), do: "1 #{one}"
  defp pluralize(n, _one, many), do: "#{n} #{many}"
end
