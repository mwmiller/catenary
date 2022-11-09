defmodule Catenary.Live.EntryViewer do
  require Logger
  use Phoenix.LiveComponent

  @impl true
  def update(%{entry: :random} = assigns, socket) do
    update(Map.merge(assigns, %{entry: Catenary.random_timeline_log()}), socket)
  end

  def update(%{entry: :none}, socket) do
    {:ok, assign(socket, card: :none)}
  end

  def update(%{store: store, entry: which, clump_id: clump_id} = assigns, socket)
      when is_atom(which) do
    targets = QuaggaDef.logs_for_name(which)

    case store |> Enum.filter(fn {_, l, _} -> l in targets end) do
      [] ->
        {:ok, assign(socket, card: :none)}

      entries ->
        entry = Enum.random(entries)

        case extract(entry, clump_id, store) do
          :error ->
            update(assigns, socket)

          card ->
            Phoenix.PubSub.local_broadcast(Catenary.PubSub, "ui", %{entry: entry})
            {:ok, assign(socket, Map.merge(assigns, %{card: card}))}
        end
    end
  end

  def update(%{store: store, entry: which, clump_id: clump_id} = assigns, socket) do
    way =
      case Catenary.blocked?(which, clump_id) do
        true ->
          %{card: :blocked}

        false ->
          %{card: extract(which, clump_id, store)}
      end

    {:ok, assign(socket, Map.merge(assigns, way))}
  end

  @impl true
  def render(%{card: :none} = assigns) do
    ~L"""
      <div class="min-w-full font-sans row-span-full">
        <h1>No data just yet</h1>
      </div>
    """
  end

  def render(%{card: :error} = assigns) do
    ~L"""
      <div class="min-w-full font-sans row-span-full">
        <h1>Unrenderable card</h1>
      </div>
    """
  end

  def render(%{card: :blocked} = assigns) do
    ~L"""
      <div id="block-wrap" class="col-span-2 overflow-y-auto max-h-screen m-2 p-x-2">
      <div class="min-w-full font-sans row-span-full">
        <h1>Blocked author</h1>
        <p>You have blocked this author. Their activity will not be available to you unless you unblock.</p>
      </div>
    </div>
    """
  end

  def render(assigns) do
    ~L"""
      <div id="entryview-wrap" class="col-span-2 overflow-y-auto max-h-screen m-2 p-x-2">
        <div class="min-w-full font-sans row-span-full">
        <img class = "float-left m-3" src="<%= Catenary.identicon(@card["author"], 8) %>">
          <h1><%= @card["title"] %></h1>
          <p class="text-sm font-light"><%= Catenary.linked_author(@card["author"], @aliases) %> &mdash; <%= nice_time(@card["published"]) %></p>
          <p><%= icon_entries(@card["back-refs"]) %>&nbsp;↹&nbsp;<%= icon_entries(@card["fore-refs"]) %></p>
        <hr/>
        <br/>
        <div class="font-light">
        <%= @card["body"] %>
        </div>
        <div class="grid grid-cols-4 mt-10 space-x-4" text-xs>
          <%= for tname <- @card["tags"] do %>
            <div class="auto text-xs text-orange-600 dark:text-amber-200"><button value="prev-tag-<%= tname %>" phx-click="nav">«</button> <button value="<%= tname %>" phx-click="view-tag"><%= tname %></button> <button value="next-tag-<%= tname %>" phx-click="nav">»</button></div>
          <% end %>
            <div class="flex flex-rows"><%= icon_entries(@card["tagged-in"]) %></div>
        </div>
      </div>
    </div>
    """
  end

  def extract({:profile, a} = entry, clump_id, si) do
    Catenary.Preferences.mark_entry(:shown, entry)

    {timeline, as_of} =
      case from_dets(a, :timelines) do
        [] ->
          {"", :latest}

        activity ->
          rev_order = activity |> Enum.reverse()
          # We extract this one twice.  But maybe there is a filter later
          %{"published" => as_of} = rev_order |> hd |> then(fn e -> extract(e, clump_id, si) end)

          groups =
            activity
            |> Enum.reverse()
            |> Enum.take(11)
            |> Enum.group_by(fn {_, l, _} -> Catenary.pretty_log_name(l) end)
            |> Enum.map(fn t -> group_list(t, clump_id, si) end)
            |> Enum.join("")

          {"<div class=\"flex flex-rows-3\">" <> groups <> "</div>", as_of}
      end

    log_map =
      si
      |> Enum.filter(fn {author, _, _} -> author == a end)
      |> Enum.group_by(fn {_, l, _} -> QuaggaDef.log_def(l) end)
      |> Enum.reject(fn {ldef, _} -> ldef == %{} end)

    items =
      for {%{name: name}, [entry | _]} <- log_map do
        "<div class=\"border-y row-auto m-2 p-1 \"><button class=\"text-xs\" value=\"" <>
          Catenary.index_to_string(entry) <>
          "\" phx-click=\"view-entry\">" <>
          String.capitalize(Atom.to_string(name)) <> "</button></div>"
      end

    others =
      case length(items) do
        0 ->
          ""

        _ ->
          "<div class=\"mt-20 flex flex-row\">" <> Enum.join(items) <> "</div>"
      end

    Map.merge(
      %{
        "author" => a,
        "title" => clump_id <> " Overview",
        "back-refs" => [],
        "tags" => [],
        "body" => Phoenix.HTML.raw(timeline <> others),
        "published" => as_of
      },
      from_refs(entry)
    )
  end

  def extract({a, l, e} = entry, clump_id, _si) do
    # We want failure to save here to fail loudly without any further work
    # But if it does fail later we don't mind having said it was shown
    Catenary.Preferences.mark_entry(:shown, {a, l, e})

    try do
      payload =
        case Baobab.log_entry(a, e, log_id: l, clump_id: clump_id) do
          %Baobab.Entry{payload: pl} ->
            pl

          _ ->
            :missing
        end

      base =
        Map.merge(
          %{
            "author" => a,
            "tags" => from_dets(entry, :tags)
          },
          from_refs(entry)
        )

      Map.merge(extract_type(payload, QuaggaDef.log_def(l)), base)
    rescue
      e ->
        Logger.warn(e)
        :error
    end
  end

  defp extract_type(:missing, _) do
    %{
      "title" => "Missing Post",
      "back-refs" => [],
      "body" => "This may become available as you sync with more peers.",
      "published" => :unknown
    }
  end

  defp extract_type(:unknown, _) do
    %{
      "title" => "Loading Error",
      "back-refs" => [],
      "body" => "This should never happen to you.",
      "published" => :unknown
    }
  end

  defp extract_type(text, %{name: :test}) do
    %{
      "title" => "Test Post, Please Ignore",
      "back-refs" => [],
      "body" => maybe_text(text),
      "published" => :unknown
    }
  end

  defp extract_type(cbor, %{name: :alias}) do
    try do
      {:ok, data, ""} = CBOR.decode(cbor)

      Map.merge(data, %{
        "title" => "Alias: ~" <> data["alias"],
        "body" => Phoenix.HTML.raw("Key: " <> data["whom"]),
        "back-refs" => maybe_refs(data["references"])
      })
    rescue
      e -> malformed(e, cbor)
    end
  end

  defp extract_type(cbor, %{name: :graph}) do
    try do
      {:ok, data, ""} = CBOR.decode(cbor)

      Map.merge(data, %{
        "title" => String.capitalize(data["action"]) <> ": " <> data["whom"],
        "body" => data["reason"],
        "back-refs" => maybe_refs(data["references"])
      })
    rescue
      e -> malformed(e, cbor)
    end
  end

  defp extract_type(cbor, %{name: :oasis}) do
    try do
      {:ok, data, ""} = CBOR.decode(cbor)

      %{
        "title" => "Oasis: " <> data["name"],
        "body" => data["host"] <> ":" <> Integer.to_string(data["port"]),
        "back-refs" => maybe_refs(data["references"]),
        "published" => data["running"]
      }
    rescue
      e -> malformed(e, cbor)
    end
  end

  defp extract_type(cbor, %{name: :journal}) do
    try do
      {:ok, data, ""} = CBOR.decode(cbor)

      Map.merge(data, %{
        "body" => data["body"] |> Earmark.as_html!() |> Phoenix.HTML.raw(),
        "back-refs" => maybe_refs(data["references"])
      })
    rescue
      e -> malformed(e, cbor)
    end
  end

  defp extract_type(cbor, %{name: :reply}) do
    try do
      {:ok, data, ""} = CBOR.decode(cbor)

      Map.merge(data, %{
        "back-refs" => maybe_refs(data["references"]),
        "body" => data["body"] |> Earmark.as_html!() |> Phoenix.HTML.raw()
      })
    rescue
      e -> malformed(e, cbor)
    end
  end

  defp extract_type(cbor, %{name: :tag}) do
    try do
      {:ok, data, ""} = CBOR.decode(cbor)

      tagdivs =
        data["tags"]
        |> Enum.map(fn t ->
          "<div class=\"text-amber-900 dark:text-amber-100\"><button value=\"" <>
            t <> "\" phx-click=\"view-tag\">" <> t <> "</button></div>"
        end)

      body = "<div>" <> Enum.join(tagdivs, "") <> "</div>"

      Map.merge(data, %{
        "title" => "Tags Added",
        "back-refs" => maybe_refs(data["references"]),
        "body" => Phoenix.HTML.raw(body)
      })
    rescue
      e -> malformed(e, cbor)
    end
  end

  defp nice_time(:unknown), do: "unknown"
  defp nice_time(:latest), do: "latest known"

  defp nice_time(t) do
    t
    |> Timex.parse!("{ISO:Extended}")
    |> Timex.Timezone.convert(Timex.Timezone.local())
    |> Timex.Format.DateTime.Formatter.format!("{YYYY}-{0M}-{0D} {kitchen}")
  end

  defp malformed(error, body) do
    Logger.debug(error)

    %{
      "title" => "Malformed Entry",
      "back-refs" => [],
      "body" => maybe_text(body),
      "published" => "unknown"
    }
  end

  defp maybe_text(t) when is_binary(t) do
    case String.printable?(t) do
      true -> t
      false -> "unprintable binary"
    end
  end

  defp maybe_text(_), do: "Not binary"

  defp maybe_refs(list, acc \\ [])
  defp maybe_refs(nil, _), do: []

  defp maybe_refs([], acc), do: Enum.reverse(acc)

  defp maybe_refs([r | rest], acc) do
    maybe_refs(rest, [List.to_tuple(r) | acc])
  end

  defp from_dets(entry, table) do
    Catenary.dets_open(table)

    val =
      case :dets.lookup(table, entry) do
        [] -> []
        [{^entry, v}] -> v
      end
      |> Enum.map(fn {_pub, v} -> v end)

    Catenary.dets_close(table)
    val
  end

  defp from_refs(entry) do
    {tags, others} =
      entry
      |> from_dets(:references)
      |> Enum.split_with(fn {_, l, _} -> QuaggaDef.base_log(l) == 749 end)

    %{"tagged-in" => tags, "fore-refs" => others}
  end

  defp icon_entries(list, acc \\ "")
  defp icon_entries([], acc), do: Phoenix.HTML.raw(acc)

  defp icon_entries([entry | rest], acc) do
    icon_entries(rest, acc <> Catenary.entry_icon_link(entry, 2) <> "&nbsp;")
  end

  defp group_list({ln, items}, clump_id, si) do
    recents =
      items
      |> Enum.take(2)
      |> Enum.map(fn e -> {e, extract(e, clump_id, si)} end)
      |> Enum.reduce("", fn {e, vals}, acc ->
        acc <>
          "<li><button " <>
          Catenary.maybe_border(e) <>
          " phx-click=\"view-entry\" value=\"" <>
          Catenary.index_to_string(e) <>
          "\">" <> vals["title"] <> "</button></li>"
      end)

    "<div class=\"flex-auto\"><h4>" <> ln <> "</h4><ul>" <> recents <> "</ul></div>"
  end
end
