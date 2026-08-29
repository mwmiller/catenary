defmodule Catenary.Live.EntryViewer do
  @moduledoc """
  LiveComponent that renders a single entry as a card: profile, text posts, media, aliases, tags, reactions, and mentions.
  """
  require Logger
  use Phoenix.LiveComponent
  alias Catenary.{Display, Preferences}

  @image_logs Catenary.image_logs()
  @impl true
  def update(%{entry: :random} = assigns, socket) do
    update(Map.merge(assigns, %{entry: Catenary.random_timeline_log()}), socket)
  end

  def update(%{entry: :none}, socket) do
    {:ok, assign(socket, card: :none)}
  end

  def update(
        %{store: store, entry: which, clump_id: clump_id, identity: identity} = assigns,
        socket
      )
      when is_atom(which) do
    targets = QuaggaDef.logs_for_name(which)

    case store |> Enum.filter(fn {_, l, _} -> l in targets end) do
      [] ->
        {:ok, assign(socket, card: :none)}

      entries ->
        entry = Enum.random(entries)

        case extract(entry, clump_id: clump_id, store: store, identity: identity, socket: socket) do
          :error ->
            update(assigns, socket)

          card ->
            Phoenix.PubSub.local_broadcast(Catenary.PubSub, "ui", %{view: :entries, entry: entry})
            {:ok, assign(socket, Map.merge(assigns, %{card: card}))}
        end
    end
  end

  def update(
        %{store: store, entry: which, clump_id: clump_id, identity: identity} = assigns,
        socket
      ) do
    way =
      case Catenary.blocked?(which, clump_id) do
        true ->
          %{card: :blocked}

        false ->
          %{
            card:
              extract(which, clump_id: clump_id, store: store, identity: identity, socket: socket)
          }
      end

    {:ok, assign(socket, Map.merge(assigns, way))}
  end

  @impl true

  def render(%{card: :none} = assigns), do: Catenary.GeneriCard.no_data_card(assigns)

  def render(%{card: :error} = assigns), do: Catenary.GeneriCard.error_card(assigns)

  def render(%{card: :blocked} = assigns) do
    ~H"""
    <div id="block-wrap" class="content-wrap">
      <div class="rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-900 p-4">
        <h1 class="text-lg font-semibold text-slate-800 dark:text-slate-100">Blocked</h1>
        <p class="text-slate-600 dark:text-slate-300">
          You have blocked this activity. It will not be available to you unless you unblock.
        </p>
      </div>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div id="entryview-wrap" class="content-wrap">
      <div class="flex flex-col gap-4">
        <div class="rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-900 p-4 flex flex-col gap-3">
          <div class="flex items-start gap-3">
            {Phoenix.HTML.raw(Display.scaled_avatar(@card["author"], 8, ["flex-none"]))}
            <div class="flex-auto min-w-0">
              <h1 class="text-lg font-semibold text-slate-800 dark:text-slate-100">
                {@card["title"]}
              </h1>
              <p class="text-sm text-slate-500 dark:text-slate-400">
                {Phoenix.HTML.raw(Display.linked_author(@card["author"], @aliases))} &mdash; {nice_time(
                  @card["published"]
                )}
              </p>
              <p class="text-xs text-slate-400 dark:text-slate-500">
                {icon_entries(@card["back-refs"])}&nbsp;↹&nbsp;{icon_entries(@card["fore-refs"])}
              </p>
            </div>
          </div>
          <div class="font-light text-slate-700 dark:text-slate-200 leading-relaxed">
            {@card["body"]}
          </div>
        </div>
        <%= if is_tuple(@entry) && tuple_size(@entry) == 3 do %>
          <div class="flex flex-row flex-wrap items-center gap-x-8 gap-y-3">
            {metabox(@card, "mentions")}
            {metabox(@card, "tags")}
            {metabox(@card, "reactions")}
            {metabox(@card, "refs", "ml-auto")}
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  def extract({:profile, a} = entry, settings) do
    clump_id = Keyword.get(settings, :clump_id)

    about = profile_about(a)
    {tabs, as_of} = profile_timeline(a, settings)
    others = profile_others(settings, a)
    mentions = profile_mentions(a)
    key = key_link(a)

    Preferences.mark_entry(:shown, entry)

    Map.merge(
      %{
        "my_profile" => a == Keyword.get(settings, :identity, "buh"),
        "author" => a,
        "title" => clump_id <> " Overview",
        "back-refs" => [],
        "tags" => [],
        "body" => Phoenix.HTML.raw(about <> mentions <> tabs <> others <> key),
        "published" => as_of
      },
      from_refs(entry)
    )
  end

  def extract({a, l, e} = entry, settings) do
    clump_id = Keyword.get(settings, :clump_id)
    ldef = l |> QuaggaDef.base_log() |> QuaggaDef.log_def()
    lname = ldef.name

    payload = payload_for({a, l, e}, lname, clump_id)

    tags = accepted(Preferences.accept_log_name?(:tag), entry, :tags)
    reactions = accepted(Preferences.accept_log_name?(:react), entry, :reactions)

    mentions =
      accepted(Preferences.accept_log_name?(:mention), entry, :mentions)
      |> Enum.map(fn k -> Display.entry_icon_link({:profile, k}, 2) end)

    all_refs = from_refs(entry)
    mark_shown(entry, all_refs)

    base =
      Map.merge(
        %{
          "author" => a,
          "tags" => tags,
          "reactions" => reactions,
          "mentions" => mentions
        },
        all_refs
      )

    Map.merge(extract_type(payload, ldef), base)
  rescue
    e ->
      Logger.warning(e)
      :error
  end

  defp payload_for({a, l, e}, lname, clump_id) do
    case lname in @image_logs do
      true ->
        Catenary.image_src_for_entry({a, l, e}, clump_id)

      false ->
        case Baobab.log_entry(a, e, log_id: l, clump_id: clump_id) do
          %Baobab.Entry{payload: pl} ->
            pl

          _ ->
            :missing
        end
    end
  end

  defp accepted(true, entry, rel), do: from_ets(entry, rel)
  defp accepted(false, _entry, _rel), do: []

  defp mark_shown(entry, all_refs) do
    case Preferences.shown?(entry) do
      false -> Preferences.mark_entries(:shown, [entry | all_refs["refs"]])
      true -> :ok
    end
  end

  defp profile_about(a) do
    about =
      case :ets.lookup(:about, a) do
        [{^a, aboot}] ->
          name =
            case aboot |> Map.get("name") do
              nil ->
                ""

              n ->
                "<h1 class=\"text-2xl font-bold text-slate-800 dark:text-slate-100\">" <>
                  n <> "</h1>"
            end

          desc =
            case aboot |> Map.get("description", "") |> MDEx.to_html() do
              {:ok, html} -> html
              _ -> ""
            end

          [name, desc]

        _ ->
          []
      end

    case about do
      [] ->
        ""

      _ ->
        "<div class=\"flex flex-col gap-2 rounded-lg bg-slate-50 px-3 py-2 dark:bg-slate-800/40\">" <>
          Enum.join(about, "") <> "</div>"
    end
  end

  defp profile_timeline(a, settings) do
    case from_ets(a, :timelines) do
      [] ->
        {"", :latest}

      activity ->
        rev_order = activity |> Enum.reverse()
        # We extract this one twice.  But maybe there is a filter later
        %{"published" => as_of} = rev_order |> hd |> then(fn e -> extract(e, settings) end)

        journals =
          Enum.filter(rev_order, fn {_, l, _} -> l in QuaggaDef.logs_for_name(:journal) end)

        replies = Enum.filter(rev_order, fn {_, l, _} -> l in QuaggaDef.logs_for_name(:reply) end)

        {profile_tabs(journals, replies, settings), as_of}
    end
  end

  # Journals and Replies are the two primary content logs for a profile.
  # Render them as a CSS-only (no server round-trip) tabbed list.
  defp profile_tabs(journals, replies, settings) do
    j = tab_list(journals, settings)
    r = tab_list(replies, settings)

    cond do
      j == "" and r == "" ->
        ""

      r == "" ->
        ~s(<div class="flex-auto p-2"><h4 class="text-xs tracking-wide text-slate-400 dark:text-slate-500">Journal</h4><ul class="list-none m-0 p-0 flex flex-col gap-1 divide-y divide-slate-200 dark:divide-slate-700">) <>
          j <> "</ul></div>"

      j == "" ->
        ~s(<div class="flex-auto p-2"><h4 class="text-xs tracking-wide text-slate-400 dark:text-slate-500">Reply</h4><ul class="list-none m-0 p-0 flex flex-col gap-1 divide-y divide-slate-200 dark:divide-slate-700">) <>
          r <> "</ul></div>"

      true ->
        ~s(<div class="flex-auto p-2">) <>
          ~s(<input type="radio" id="ptab-journal" name="profile-tabs" class="hidden peer/ptabj" checked>) <>
          ~s(<input type="radio" id="ptab-reply" name="profile-tabs" class="hidden peer/ptabr">) <>
          ~s(<div class="flex gap-1 border-b border-slate-200 dark:border-slate-700 pb-px">) <>
          ~s(<label for="ptab-journal" class="cursor-pointer rounded-t-md px-3 py-1 text-sm font-medium text-slate-500 dark:text-slate-400 hover:text-slate-700 dark:hover:text-slate-200 peer-checked/ptabj:bg-amber-500/10 peer-checked/ptabj:text-amber-700 dark:peer-checked/ptabj:text-amber-300">Journal</label>) <>
          ~s(<label for="ptab-reply" class="cursor-pointer rounded-t-md px-3 py-1 text-sm font-medium text-slate-500 dark:text-slate-400 hover:text-slate-700 dark:hover:text-slate-200 peer-checked/ptabr:bg-amber-500/10 peer-checked/ptabr:text-amber-700 dark:peer-checked/ptabr:text-amber-300">Reply</label>) <>
          ~s(</div>) <>
          ~s(<div class="hidden py-2 peer-checked/ptabj:block">) <>
          j <>
          ~s(</div>) <>
          ~s(<div class="hidden py-2 peer-checked/ptabr:block">) <>
          r <>
          ~s(</div>) <>
          ~s(</div>)
    end
  end

  defp tab_list(entries, settings) do
    case entries |> Enum.take(7) |> Enum.map(fn e -> tab_item(e, settings) end) do
      [] ->
        ""

      items ->
        ~s(<ul class="list-none m-0 p-0 flex flex-col gap-1 divide-y divide-slate-200 dark:divide-slate-700">) <>
          Enum.join(items, "") <> "</ul>"
    end
  end

  defp tab_item(e, settings) do
    vals = extract(e, settings)
    {ident, _l, _s} = e
    {:safe, ava} = Display.scaled_avatar(ident, 2, ["h-4 w-4 rounded-full object-cover"])

    when_new =
      if Preferences.shown?(e) do
        ""
      else
        ~s(<span class="ml-2 w-1.5 h-1.5 shrink-0 rounded-full bg-amber-400 dark:bg-amber-500"></span>)
      end

    ~s(<li><button class="flex items-center gap-2 rounded-md px-2 py-1 text-sm text-slate-700 dark:text-slate-200 hover:bg-slate-100 dark:hover:bg-slate-800/60 text-left" phx-click="view-entry" value="#{Catenary.index_to_string(e)}">) <>
      ava <>
      ~s(<span class="truncate">#{vals["title"]}</span>) <> when_new <> "</button></li>"
  end

  defp profile_others(settings, a) do
    items =
      settings
      |> Keyword.get(:store)
      |> Enum.filter(fn {author, _, _} -> author == a end)
      |> Enum.group_by(fn {_, l, _} -> QuaggaDef.log_def(l) end)
      |> Enum.reject(fn {ldef, _} -> ldef == %{} end)
      |> Enum.filter(fn {%{name: name}, _} -> Preferences.accept_log_name?(name) end)

    case length(items) do
      0 ->
        ""

      _ ->
        buttons =
          items
          |> Enum.reduce([], fn {%{name: name}, [entry | _]}, acc ->
            [
              ~s(<div class="flex-none"><button class="rounded-md border border-slate-200 dark:border-slate-700 bg-slate-50 dark:bg-slate-800 px-2 py-0.5 text-xs text-amber-700 dark:text-amber-300 hover:border-amber-500 hover:text-amber-600 dark:hover:border-amber-400 dark:hover:text-amber-200" value=") <>
                Catenary.index_to_string(entry) <>
                ~s(" phx-click="view-entry">) <>
                String.capitalize(Atom.to_string(name)) <> "</button></div>"
              | acc
            ]
          end)
          |> Enum.reverse()
          |> Enum.join()

        ~s(<div class="flex-auto p-2"><h4 class="text-xs tracking-wide text-slate-400 dark:text-slate-500">Logs</h4><div class="flex flex-row flex-wrap items-center gap-1.5">) <>
          buttons <> "</div></div>"
    end
  end

  defp profile_mentions(a) do
    case from_ets({"", a}, :mentions) |> Enum.reject(&Preferences.shown?/1) do
      [] ->
        ""

      entries ->
        {:safe, icons} = entries |> Enum.reverse() |> icon_entries

        ~s(<h4 class="text-xs tracking-wide text-slate-400 dark:text-slate-500">Unshown mentions</h4><div class="p-2 flex flex-row">) <>
          icons <> "</div>"
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
      "title" => Display.entry_title(:test, %{}),
      "back-refs" => [],
      "body" => maybe_text(text),
      "published" => :unknown
    }
  end

  defp extract_type(src_uri, %{name: mime}) when mime in @image_logs do
    %{
      "title" => Display.entry_title(:image, %{}),
      "back-refs" => [],
      "body" =>
        Phoenix.HTML.raw(
          "<img class=\"rounded-lg border border-slate-200 dark:border-slate-700 max-w-full h-auto\" src=\"" <>
            src_uri <> "\">"
        ),
      "published" => :unknown
    }
  end

  defp extract_type(cbor, %{name: :alias}) do
    {:ok, data, ""} = CBOR.decode(cbor)

    Map.merge(data, %{
      "title" => Display.entry_title(:alias, data),
      "body" => Phoenix.HTML.raw(key_link(data["whom"])),
      "back-refs" => maybe_refs(data["references"])
    })
  rescue
    e -> malformed(e, cbor)
  end

  defp extract_type(cbor, %{name: :about}) do
    {:ok, data, ""} = CBOR.decode(cbor)

    Map.merge(data, %{
      "title" => Display.entry_title(:about, data),
      "body" =>
        Phoenix.HTML.raw(
          "Visit profile for latest view.  Maybe this will show the update someday."
        ),
      "back-refs" => maybe_refs(data["references"])
    })
  rescue
    e -> malformed(e, cbor)
  end

  defp extract_type(cbor, %{name: :mention}) do
    {:ok, data, ""} = CBOR.decode(cbor)

    keys = data["mentions"] |> Enum.join(", ")

    Map.merge(data, %{
      "title" => Display.entry_title(:mention, data),
      "body" => Phoenix.HTML.raw("Keys: " <> keys),
      "back-refs" => maybe_refs(data["references"])
    })
  rescue
    e -> malformed(e, cbor)
  end

  defp extract_type(cbor, %{name: :graph}) do
    {:ok, data, ""} = CBOR.decode(cbor)
    action = data["action"]

    common =
      Map.merge(data, %{
        "title" => Display.entry_title(:graph, data),
        "back-refs" => maybe_refs(data["references"])
      })

    case action do
      "block" ->
        Map.merge(common, %{
          "body" =>
            Phoenix.HTML.raw(
              key_link(data["whom"]) <> "<div class=\"mt-5\">" <> data["reason"] <> "</div>"
            )
        })

      "unblock" ->
        Map.merge(common, %{
          "body" =>
            Phoenix.HTML.raw(
              key_link(data["whom"]) <> "<div class=\"mt-5\">" <> data["reason"] <> "</div>"
            )
        })

      "logs" ->
        Map.merge(common, %{
          "body" =>
            Phoenix.HTML.raw(
              "Accept: " <>
                Enum.join(data["accept"], ", ") <>
                "<br/>Reject: " <> Enum.join(data["reject"], ", ")
            )
        })
    end
  rescue
    e -> malformed(e, cbor)
  end

  defp extract_type(cbor, %{name: :react}) do
    {:ok, data, ""} = CBOR.decode(cbor)

    Map.merge(data, %{
      "title" => Display.entry_title(:react, data),
      "body" => Enum.join(data["reactions"], " "),
      "back-refs" => maybe_refs(data["references"])
    })
  rescue
    e -> malformed(e, cbor)
  end

  defp extract_type(cbor, %{name: :oasis}) do
    {:ok, data, ""} = CBOR.decode(cbor)

    body =
      case {"<p>" <>
              data["host"] <> ":" <> Integer.to_string(data["port"]) <> "</p>", data["operator"]} do
        {b, nil} -> b
        {b, op} -> b <> "<p>operated by:</p><p>" <> key_link(op) <> "</p>"
      end

    %{
      "title" => Display.entry_title(:oasis, data),
      "body" => Phoenix.HTML.raw(body),
      "back-refs" => maybe_refs(data["references"]),
      "published" => data["running"]
    }
  rescue
    e -> malformed(e, cbor)
  end

  defp extract_type(cbor, %{name: type}) when type in [:journal, :reply],
    do: text_post(type, cbor)

  defp extract_type(cbor, %{name: :tag}) do
    {:ok, data, ""} = CBOR.decode(cbor)

    tagdivs =
      data["tags"]
      |> Enum.map(fn t ->
        "<div class=\"text-amber-900 dark:text-amber-100\"><button value=\"" <>
          t <> "\" phx-click=\"view-tag\">" <> t <> "</button></div>"
      end)

    body = "<div>" <> Enum.join(tagdivs, "") <> "</div>"

    Map.merge(data, %{
      "title" => Display.entry_title(:tag, data),
      "back-refs" => maybe_refs(data["references"]),
      "body" => Phoenix.HTML.raw(body)
    })
  rescue
    e -> malformed(e, cbor)
  end

  defp key_link(key),
    do:
      Display.entry_icon_link({:profile, key}, 2) <>
        "&nbsp;&nbsp;<span class=\"text-slate-500 dark:text-slate-400 break-all\">Key: " <>
        key <> "</span>"

  defp nice_time(:unknown), do: "timeless"
  defp nice_time(:latest), do: "latest known"

  defp nice_time(t) do
    case DateTime.from_iso8601(t, :extended) do
      {:ok, dt, _} -> nice_time_dt(dt)
      _ -> "timeless"
    end
  rescue
    _ -> "timeless"
  end

  defp nice_time_dt(%DateTime{} = dt) do
    local =
      case DateTime.shift_zone(dt, local_zone()) do
        {:ok, z} -> z
        _ -> DateTime.shift_zone!(dt, "Etc/UTC")
      end

    "#{Date.to_iso8601(local)} #{kitchen(local)}"
  end

  # Machine-local IANA zone: prefer $TZ, otherwise derive from the
  # /etc/localtime symlink target (e.g. ".../America/New_York"), else UTC.
  defp local_zone do
    case System.get_env("TZ") do
      tz when is_binary(tz) and tz != "" -> tz
      _ -> local_zone_from_file()
    end
  end

  defp local_zone_from_file do
    case :file.read_link("/etc/localtime") do
      {:ok, target} ->
        target
        |> to_string()
        |> String.split("/")
        |> Enum.reverse()
        |> Enum.take_while(&(&1 != "zoneinfo"))
        |> Enum.reverse()
        |> Enum.join("/")

      _ ->
        "Etc/UTC"
    end
  end

  defp kitchen(%{hour: 0, minute: m}), do: "12:#{pad2(m)} AM"
  defp kitchen(%{hour: 12, minute: m}), do: "12:#{pad2(m)} PM"
  defp kitchen(%{hour: h, minute: m}) when h < 12, do: "#{h}:#{pad2(m)} AM"
  defp kitchen(%{hour: h, minute: m}), do: "#{h - 12}:#{pad2(m)} PM"

  defp pad2(n), do: n |> Integer.to_string() |> String.pad_leading(2, "0")

  defp malformed(error, body) do
    Logger.debug(error)

    %{
      "title" => "Malformed Entry",
      "back-refs" => [],
      "body" => maybe_text(body),
      "published" => :unknown
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

  defp from_ets(entry, table) do
    case :ets.lookup(table, entry) do
      [] -> []
      [{^entry, v}] -> v
    end
    |> Enum.map(fn {_pub, v} -> v end)
  end

  @reply_ref_ids QuaggaDef.logs_for_name(:reply)
  defp from_refs(entry) do
    {replies, refs} =
      entry
      |> from_ets(:references)
      |> Enum.split_with(fn {_, l, _} -> l in @reply_ref_ids end)

    %{"refs" => refs, "fore-refs" => replies}
  end

  defp metabox(data, which, extra \\ "") do
    case data[which] do
      [] ->
        ""

      stuff ->
        """
        <div class="flex flex-row flex-wrap items-center gap-x-6 gap-y-2 #{extra}">
        """ <>
          metafill(stuff, which, "") <>
          "</div>"
    end
    |> Phoenix.HTML.raw()
  end

  defp metafill([], _, acc), do: acc
  defp metafill([h | t], "mentions", acc), do: metafill(t, "mentions", acc <> h)

  defp metafill([h | t], "tags", acc) do
    metafill(
      t,
      "tags",
      acc <>
        ~s(<span class="inline-flex items-center gap-1 text-slate-500 dark:text-slate-400"><button class="hover:text-amber-600 dark:hover:text-amber-300" value="prev-tag-) <>
        h <>
        ~s(" phx-click="nav">«</button> <button class="text-amber-700 dark:text-amber-300 hover:text-amber-600 dark:hover:text-amber-200" value=") <>
        h <>
        ~s("  phx-click="view-tag">) <>
        h <>
        ~s(</button> <button class="hover:text-amber-600 dark:hover:text-amber-300" value="next-tag-) <>
        h <> ~s(" phx-click="nav">»</button></span>)
    )
  end

  defp metafill(reactions, "reactions", _), do: Enum.join(reactions, " ")

  defp metafill(refs, "refs", _) do
    {:safe, val} = icon_entries(refs)
    val
  end

  defp metafill(_, _, _), do: ""

  defp icon_entries(list, acc \\ "")
  defp icon_entries([], acc), do: Phoenix.HTML.raw(acc)

  defp icon_entries([entry | rest], acc) do
    icon_entries(rest, acc <> Display.entry_icon_link(entry, 2) <> "&nbsp;")
  end

  defp text_post(type, cbor) do
    {:ok, data, ""} = CBOR.decode(cbor)

    Map.merge(data, %{
      "title" => Display.entry_title(type, data),
      "back-refs" => maybe_refs(data["references"]),
      "body" => data["body"] |> MDEx.to_html!() |> Phoenix.HTML.raw()
    })
  rescue
    e -> malformed(e, cbor)
  end
end
