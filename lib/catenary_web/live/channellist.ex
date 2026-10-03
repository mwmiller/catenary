defmodule Catenary.Live.ChannelList do
  @moduledoc """
  LiveComponent listing what a channel currently holds: its entries, newest
  published first, each one linked to its entry in the viewer.

  The same list answers both places a channel is browsable — under a
  running app's pane in `Catenary.Live.AppViewer`, and in the playground's
  left rail for the draft's own channel — because "a channel's entries,
  newest first" is one shape and two mounts rather than two shapes. The
  host's `channel` op is deliberately not used here: that answer belongs
  to a *module* on the wire, with its cursor, caps and visibility rules
  applied as an app is judged, while this is the UI reading the store the
  way the UI reads it anywhere else.

  Rows are memoised on the tuple the caller passes — clump, channel, and
  the two counters that say the answer could have changed — so a parent
  that re-renders on every keystroke or trace line does not re-read the
  store; a publish or an index bump moves a counter and the next render
  reads again.
  """
  use Phoenix.LiveComponent

  alias Catenary.{Apps, Display}

  # What one rail or pane shows of a busy channel. The wire's `channel` op
  # pages past this; the list is a glance, not a page, so it stops.
  @max_rows 20

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:channel_bump, fn -> 0 end)
     |> assign_new(:index_version, fn -> 0 end)
     |> assign_rows()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class="flex flex-col gap-1">
      <h2 class="px-1 text-xs font-semibold uppercase tracking-wide text-slate-500 dark:text-slate-400">
        Channel
      </h2>
      <p :if={@rows == []} class="px-1 text-xs text-slate-400 dark:text-slate-500">
        Nothing published here yet.
      </p>
      <ol :if={@rows != []} class="flex flex-col gap-1">
        <li :for={row <- @rows} class="rounded px-1.5 py-1 hover:bg-slate-100 dark:hover:bg-slate-800">
          <div class="flex items-baseline justify-between gap-2">
            <span class="text-[10px] font-bold uppercase tracking-wide text-slate-400 dark:text-slate-500">
              {row.type}
            </span>
            <span class="shrink-0 text-[10px] text-slate-400 dark:text-slate-500">
              {row.published}
            </span>
          </div>
          <div class="break-words text-xs text-slate-700 dark:text-slate-300">
            {Phoenix.HTML.raw(
              Display.view_entry_button(
                {row.pk, row.log_id, row.seq},
                Phoenix.HTML.html_escape(row.summary)
              )
            )}
          </div>
        </li>
      </ol>
    </div>
    """
  end

  # Resolved per answer rather than per render: the parent repaints for
  # reasons that have nothing to do with the channel, and reading the
  # store for each of them would make typing in the editor a store scan.
  defp assign_rows(socket) do
    %{clump_id: clump_id, pk: pk, slug: slug} = socket.assigns

    key =
      {clump_id, pk, slug, socket.assigns.channel_bump, socket.assigns.index_version}

    if socket.assigns[:rows_for] == key do
      socket
    else
      assign(socket, rows: rows(clump_id, pk, slug), rows_for: key)
    end
  end

  # The same order the wire's `channel` op answers in — published, then
  # where it landed, then its sequence — so the list and what a module
  # reads agree on which entry is newest.
  defp rows(clump_id, pk, slug) do
    Apps.channel_entries(clump_id, pk, slug)
    |> Enum.map(fn {entry_pk, log_id, entry} ->
      data = decode(entry.payload)

      %{
        pk: entry_pk,
        log_id: log_id,
        seq: entry.seqnum,
        type: Map.get(data, "type", "entry"),
        published: published(data),
        summary: summary(data, log_id)
      }
    end)
    |> Enum.sort_by(fn row -> {row.published, row.log_id, row.seq} end, :desc)
    |> Enum.take(@max_rows)
  end

  # `published` doubles as the sort key, so an entry without one still
  # sorts — below everything that has a date, rather than raising.
  defp published(data) do
    case Map.get(data, "published") do
      t when is_binary(t) -> t
      _ -> ""
    end
  end

  defp summary(data, log_id) do
    text = Map.get(data, "text") || Map.get(data, "description")

    titled =
      case text do
        nil -> to_string(Display.entry_title(log_id, data))
        _ -> text
      end

    first_line = titled |> String.split("\n", parts: 2) |> hd() |> String.trim()

    if String.length(first_line) > 140 do
      String.slice(first_line, 0, 140) <> "…"
    else
      first_line
    end
  end

  defp decode(payload) do
    case CBOR.decode(payload) do
      {:ok, data, ""} when is_map(data) -> data
      _ -> %{}
    end
  rescue
    _ -> %{}
  end
end
