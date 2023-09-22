defmodule Catenary.Live.EntryViewer do
  require Logger
  use Phoenix.LiveComponent
  alias Catenary.Preferences

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
    ~L"""
      <div id="block-wrap" class="col-span-2 overflow-y-auto max-h-screen m-2 p-x-2">
      <div class="min-w-full font-sans row-span-full">
        <h1>Blocked</h1>
        <p>You have blocked this activity. It will not be available to you unless you unblock.</p>
      </div>
    </div>
    """
  end

  def render(assigns) do
    ~L"""
      <div id="entryview-wrap" class="col-span-2 overflow-y-auto max-h-screen m-2 p-x-2">
        <div class="min-w-full font-sans row-span-full">
          <%= Catenary.scaled_avatar(@card["author"], 8, ["float-left",  "m-3"]) %>
          <h1><%= @card["title"] %></h1>
          <p class="text-sm font-light"><%= Catenary.linked_author(@card["author"], @aliases) %> &mdash; <%= nice_time(@card["published"]) %></p>
          <p><%= icon_entries(@card["back-refs"]) %>&nbsp;↹&nbsp;<%= icon_entries(@card["fore-refs"]) %></p>
        <hr class="mb-3"/>
         <div class="font-light">
          <%= @card["body"] %>
         </div>
        </div>
        <%= if is_tuple(@entry) && tuple_size(@entry) == 3 do %>
          <div class="flex flex-row">
          <%= metabox(@card, "mentions") %>
          <%= metabox(@card, "tags") %>
          <%= metabox(@card, "reactions") %>
          <%= metabox(@card, "refs") %>
          </div>
        <% end %>
    </div>
    """
  end

  defp inna_box(bits, config, bobs \\ "")
  defp inna_box([], _config, ""), do: ""

  # This comment is for the tailwind preprocessor
  # border-dashed border-dotted border-hidden border-double border-none border-solid

  # Yeah, we use integer strings, what of it?
  defp inna_box([], config, acc) do
    "<div class=\"p-3 m-5 border border-" <>
      Keyword.get(config, :border, "solid") <>
      " grid " <> "grid-cols-" <> Keyword.get(config, :cols, "1") <> "\">" <> acc <> "</div>"
  end

  defp inna_box(["" | rest], config, acc), do: inna_box(rest, config, acc)
  defp inna_box([jabba | rest], config, acc), do: inna_box(rest, config, acc <> jabba)

  def extract({:profile, a} = entry, settings) do
    clump_id = Keyword.get(settings, :clump_id)

    about =
      case :ets.lookup(:about, a) do
        [{^a, aboot}] ->
          name =
            case aboot |> Map.get("name") do
              nil -> ""
              n -> "<h1>" <> n <> "</h1>"
            end

          desc =
            case aboot |> Map.get("description", "") |> Earmark.as_html() do
              {:ok, html, _} -> html
              _ -> ""
            end

          [name, desc]

        _ ->
          []
      end
      |> inna_box(cols: "1", border: "dashed")

    {timeline, as_of} =
      case from_ets(a, :timelines) do
        [] ->
          {"", :latest}

        activity ->
          rev_order = activity |> Enum.reverse()
          # We extract this one twice.  But maybe there is a filter later
          %{"published" => as_of} = rev_order |> hd |> then(fn e -> extract(e, settings) end)

          groups =
            rev_order
            |> Enum.take(23)
            |> Enum.group_by(fn {_, l, _} -> Catenary.pretty_log_name(l) end)
            |> Enum.map(fn t -> group_list(t, settings) end)
            |> inna_box(cols: "1", border: "dotted")

          {groups, as_of}
      end

    items =
      settings
      |> Keyword.get(:store)
      |> Enum.filter(fn {author, _, _} -> author == a end)
      |> Enum.group_by(fn {_, l, _} -> QuaggaDef.log_def(l) end)
      |> Enum.reject(fn {ldef, _} -> ldef == %{} end)
      |> Enum.filter(fn {%{name: name}, _} -> Preferences.accept_log_name?(name) end)

    others =
      case length(items) do
        0 ->
          ""

        _ ->
          items
          |> Enum.reduce([], fn {%{name: name}, [entry | _]}, a ->
            [
              "<div class=\"p-1\"><button class=\"text-xs\" value=\"" <>
                Catenary.index_to_string(entry) <>
                "\" phx-click=\"view-entry\">" <>
                String.capitalize(Atom.to_string(name)) <> "</button></div>"
              | a
            ]
          end)
          |> Enum.reverse()
          |> inna_box(cols: "5", border: "double")
      end

    mentions =
      case from_ets({"", a}, :mentions) |> Enum.reject(&Preferences.shown?/1) do
        [] ->
          ""

        entries ->
          {:safe, icons} = entries |> Enum.reverse() |> icon_entries

          "<h4 class=\"mt-5\">Unshown mentions</h4><div class=\"p-2 flex flex-row\">" <>
            icons <> "</div>"
      end

    Preferences.mark_entry(:shown, entry)

    key = key_link(a)

    Map.merge(
      %{
        "my_profile" => a == Keyword.get(settings, :identity, "buh"),
        "author" => a,
        "title" => clump_id <> " Overview",
        "back-refs" => [],
        "tags" => [],
        "body" => Phoenix.HTML.raw(key <> about <> mentions <> timeline <> others),
        "published" => as_of
      },
      from_refs(entry)
    )
  end

  def extract({a, l, e} = entry, settings) do
    clump_id = Keyword.get(settings, :clump_id)
    ldef = l |> QuaggaDef.base_log() |> QuaggaDef.log_def()
    lname = ldef.name

    try do
      payload =
        case lname in @image_logs do
          true ->
            Catenary.image_src_for_entry(entry, clump_id)

          false ->
            case Baobab.log_entry(a, e, log_id: l, clump_id: clump_id) do
              %Baobab.Entry{payload: pl} ->
                pl

              _ ->
                :missing
            end
        end

      tags =
        case Preferences.accept_log_name?(:tag) do
          true -> from_ets(entry, :tags)
          false -> []
        end

      reactions =
        case Preferences.accept_log_name?(:react) do
          true -> from_ets(entry, :reactions)
          false -> []
        end

      mentions =
        case Preferences.accept_log_name?(:mention) do
          true -> from_ets(entry, :mentions)
          false -> []
        end
        |> Enum.map(fn k -> Catenary.entry_icon_link({:profile, k}, 2) end)

      all_refs = from_refs(entry)

      case Preferences.shown?(entry) do
        false -> Preferences.mark_entries(:shown, [entry | all_refs["refs"]])
        true -> :ok
      end

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
      "title" => added_title("Test Post"),
      "back-refs" => [],
      "body" => maybe_text(text),
      "published" => :unknown
    }
  end

  defp extract_type(src_uri, %{name: mime}) when mime in @image_logs do
    %{
      "title" => added_title("Image Added"),
      "back-refs" => [],
      "body" => Phoenix.HTML.raw("<img src=\"" <> src_uri <> "\">"),
      "published" => :unknown
    }
  end

  defp extract_type(cbor, %{name: :alias}) do
    try do
      {:ok, data, ""} = CBOR.decode(cbor)

      Map.merge(data, %{
        "title" => added_title("Alias: ~" <> data["alias"]),
        "body" => Phoenix.HTML.raw(key_link(data["whom"])),
        "back-refs" => maybe_refs(data["references"])
      })
    rescue
      e -> malformed(e, cbor)
    end
  end

  defp extract_type(cbor, %{name: :about}) do
    try do
      {:ok, data, ""} = CBOR.decode(cbor)

      Map.merge(data, %{
        "title" => added_title("Profile Update"),
        "body" =>
          Phoenix.HTML.raw(
            "Visit profile for latest view.  Maybe this will show the update someday."
          ),
        "back-refs" => maybe_refs(data["references"])
      })
    rescue
      e -> malformed(e, cbor)
    end
  end

  defp extract_type(cbor, %{name: :mention}) do
    try do
      {:ok, data, ""} = CBOR.decode(cbor)

      keys = data["mentions"] |> Enum.join(", ")

      Map.merge(data, %{
        "title" => added_title("Mention"),
        "body" => Phoenix.HTML.raw("Keys: " <> keys),
        "back-refs" => maybe_refs(data["references"])
      })
    rescue
      e -> malformed(e, cbor)
    end
  end

  defp extract_type(cbor, %{name: :graph}) do
    try do
      {:ok, data, ""} = CBOR.decode(cbor)
      action = data["action"]

      common =
        Map.merge(data, %{
          "title" => added_title(String.capitalize(data["action"])),
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
  end

  defp extract_type(cbor, %{name: :react}) do
    try do
      {:ok, data, ""} = CBOR.decode(cbor)

      Map.merge(data, %{
        "title" => added_title("Reactions Added"),
        "body" => Enum.join(data["reactions"], " "),
        "back-refs" => maybe_refs(data["references"])
      })
    rescue
      e -> malformed(e, cbor)
    end
  end

  defp extract_type(cbor, %{name: :oasis}) do
    try do
      {:ok, data, ""} = CBOR.decode(cbor)

      body =
        case {"<p>" <>
                data["host"] <> ":" <> Integer.to_string(data["port"]) <> "</p>",
              data["operator"]} do
          {b, nil} -> b
          {b, op} -> b <> "<p>operated by:</p><p>" <> key_link(op) <> "</p>"
        end

      %{
        "title" => added_title("Oasis: " <> data["name"]),
        "body" => Phoenix.HTML.raw(body),
        "back-refs" => maybe_refs(data["references"]),
        "published" => data["running"]
      }
    rescue
      e -> malformed(e, cbor)
    end
  end

  defp extract_type(cbor, %{name: :journal}), do: text_post(cbor)
  defp extract_type(cbor, %{name: :reply}), do: text_post(cbor)

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
        "title" => added_title("Tags Added"),
        "back-refs" => maybe_refs(data["references"]),
        "body" => Phoenix.HTML.raw(body)
      })
    rescue
      e -> malformed(e, cbor)
    end
  end

  defp key_link(key),
    do: Catenary.entry_icon_link({:profile, key}, 2) <> "&nbsp;&nbsp; Key: " <> key

  defp nice_time(:unknown), do: "timeless"
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

  defp metabox(data, which) do
    case data[which] do
      [] ->
        ""

      stuff ->
        """
        <div class="flex-auto mt-11 p-3 border-t border-1 dark:border-stone-500 border-grey-900 justify-center">
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
        "<div class=\"auto text-xs text-orange-600 dark:text-amber-200\"><button value=\"prev-tag-" <>
        h <>
        "\" phx-click=\"nav\">«</button> <button value=\"" <>
        h <>
        "\"  phx-click=\"view-tag\">" <>
        h <> "</button> <button value=\"next-tag-" <> h <> "\" phx-click=\"nav\">»</button></div>"
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
    icon_entries(rest, acc <> Catenary.entry_icon_link(entry, 2) <> "&nbsp;")
  end

  defp group_list({ln, items}, settings) do
    recents =
      items
      |> Enum.take(5)
      |> Enum.map(fn e -> {e, extract(e, settings)} end)
      |> Enum.reduce("", fn {e, vals}, acc ->
        acc <>
          "<li><button class=\"" <>
          Enum.join(Catenary.maybe_border(e), " ") <>
          "\" phx-click=\"view-entry\" value=\"" <>
          Catenary.index_to_string(e) <>
          "\">" <> vals["title"] <> "</button></li>"
      end)

    "<div class=\"min-w-full p-2\"><h4>" <> ln <> "</h4><ul>" <> recents <> "</ul></div>"
  end

  defp added_title(title), do: "⸤" <> title <> "⸣"

  defp text_post(cbor) do
    try do
      {:ok, data, ""} = CBOR.decode(cbor)

      title =
        case data["title"] do
          <<>> -> added_title("untitled")
          t -> t
        end

      Map.merge(data, %{
        "title" => title,
        "back-refs" => maybe_refs(data["references"]),
        "body" => data["body"] |> Earmark.as_html!() |> Phoenix.HTML.raw()
      })
    rescue
      e -> malformed(e, cbor)
    end
  end
end
