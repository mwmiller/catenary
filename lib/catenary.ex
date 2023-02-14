defmodule Catenary do
  @moduledoc """
  Catenary keeps the contexts that define your domain
  and business logic.
  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """
  @dets_tables %{
    aliases: "aliases.dets",
    graph: "social_graph.dets",
    mentions: "mentions.dets",
    prefs: "preferences.dets",
    reactions: "reactions.dets",
    references: "references.dets",
    tags: "tags.dets",
    timelines: "timelines.dets"
  }

  @image_logs QuaggaDef.log_defs()
              |> Enum.reduce([], fn {_lid, %{type: t, name: n}}, a ->
                case is_binary(t) do
                  true ->
                    case String.starts_with?(t, "image/") do
                      true -> [n | a]
                      false -> a
                    end

                  false ->
                    a
                end
              end)

  def image_logs, do: @image_logs

  def image_src_for_entry({a, l, e}, clump_id) do
    %{name: mime} = l |> QuaggaDef.base_log() |> QuaggaDef.log_def()

    Path.join([
      "/cat_images",
      clump_id,
      a,
      Integer.to_string(l),
      Integer.to_string(e) <>
        "." <> Atom.to_string(mime)
    ])
  end

  def short_id(id, {_, aliases}) do
    string =
      case Map.get(aliases, id) do
        nil -> String.slice(id, 0..10)
        ali -> ali
      end

    "~" <> string
  end

  def alias_state() do
    aliases =
      :ets.match(:aliases, :"$1")
      |> Enum.reject(fn [{a, _}] -> is_atom(a) end)
      |> Enum.reduce(%{}, fn [{a, n}], acc -> Map.put(acc, a, n) end)

    {:ok, aliases}
  end

  def profile_items_state() do
    # This might become more complicated and inclusive later
    whoami = Catenary.Preferences.get(:identity)

    profile_items =
      case :ets.lookup(:mentions, {"", whoami}) do
        [] -> []
        [{{"", ^whoami}, items}] -> Enum.map(items, fn {_t, e} -> e end)
      end

    {:ok, MapSet.new(profile_items)}
  end

  def id_for_key(key), do: find_id_for_key(Baobab.Identity.list(), key)
  defp find_id_for_key([], key), do: {:error, "No identity found for key " <> key}
  defp find_id_for_key([{ali, key} | _], key), do: ali
  defp find_id_for_key([_ | rest], key), do: find_id_for_key(rest, key)

  def scaled_avatar(id, mag, classes \\ []) do
    ss = Integer.to_string(mag * 8)

    uri =
      case :ets.lookup(:avatars, id) do
        [{^id, {a, l, e, cid}}] ->
          p = image_src_for_entry({a, l, e}, cid)
          :ets.insert(:avatars, {id, p})
          p

        [{^id, v}] ->
          v

        [] ->
          val = svg_identicon(id, mag)

          :ets.insert(:avatars, {id, val})
          val
      end

    Phoenix.HTML.raw(
      "<img class=\"" <>
        Enum.join(classes, " ") <>
        "\"  width=" <> ss <> " height=" <> ss <> " src=\"" <> uri <> "\">"
    )
  end

  defp svg_identicon(id, mag),
    do:
      "data:image/svg+xml;base64," <>
        Excon.ident(id, base64: true, type: :svg, magnification: mag)

  @list_sep "‑"
  def index_list_to_string(indices) when is_list(indices) do
    indices |> Enum.map(fn i -> index_to_string(i) end) |> Enum.join(@list_sep)
  end

  def index_list_to_string(_), do: :error

  def index_to_string(tuple) do
    tuple |> Tuple.to_list() |> Enum.map(fn e -> to_string(e) end) |> Enum.join("⋀")
  end

  def string_to_index_list(string) when is_binary(string) do
    string |> String.split(@list_sep, trim: true) |> Enum.map(fn s -> string_to_index(s) end)
  end

  def string_to_index_list(_), do: :error

  def string_to_index(string) do
    # We assume all psuedo-entries are two-element tagged
    # All three elements are "real" indices.
    case String.split(string, "⋀") do
      [a, l, e] -> {a, String.to_integer(l), String.to_integer(e)}
      [t, w] -> {String.to_existing_atom(t), w}
      _ -> :error
    end
  end

  def linked_author(author, aliases, type \\ :button)
  def linked_author({a, _, _}, aliases, type), do: linked_author(a, aliases, type)

  def linked_author(a, aliases, :button) do
    view_entry_button({:profile, a}, short_id(a, aliases)) |> Phoenix.HTML.raw()
  end

  def linked_author(a, aliases, :href) do
    Phoenix.HTML.raw("<a href=\"/authors/" <> a <> "\">" <> short_id(a, aliases) <> "</a>")
  end

  defp view_entry_button(entry, {:safe, contents}), do: view_entry_button(entry, contents)

  defp view_entry_button(entry, contents) do
    "<button value=\"" <>
      Catenary.index_to_string(entry) <>
      "\" phx-click=\"view-entry\">" <> contents <> "</button>"
  end

  def entry_icon_link({a, _, _} = entry, size),
    do: view_entry_button(entry, scaled_avatar(a, size, maybe_border(entry)))

  def entry_icon_link({:profile, a} = entry, size),
    do: view_entry_button(entry, scaled_avatar(a, size, maybe_border(entry)))

  def maybe_border(entry) do
    case Catenary.Preferences.shown?(entry) do
      true -> ["mx-auto"]
      false -> ["mx-auto", "new-border", "rounded"]
    end
  end

  def dets_open(table) do
    filename =
      Path.join([
        Application.get_env(:catenary, :application_dir, "~/.catenary"),
        Map.fetch!(@dets_tables, table)
      ])
      |> Path.expand()
      |> to_charlist

    :dets.open_file(table, file: filename)
  end

  # For symmetry, but maybe we'll have something we want to do here.
  def dets_close(table), do: :dets.close(table)

  @timeline_logs [:journal, :reply]
  def timeline_logs, do: @timeline_logs
  def random_timeline_log(), do: @timeline_logs |> Enum.random()

  # Let's not delve into why I hate using templates
  def log_submit_button do
    """
    <hr/>
    <button phx-disable-with="𝄇" type="submit">➲</button>
    """
    |> Phoenix.HTML.raw()
  end

  def pretty_log_name(log_id) do
    case QuaggaDef.log_id_unpack(log_id) do
      {base_log, _} ->
        base_log
        |> QuaggaDef.log_def()
        |> Map.get(:name, :unknown)
        |> cap_atom_string

      _ ->
        ""
    end
  end

  def all_pretty_log_pairs() do
    QuaggaDef.log_defs()
    |> Enum.map(fn {_id, %{name: n}} -> {cap_atom_string(n), n} end)
  end

  defp cap_atom_string(a), do: a |> Atom.to_string() |> String.capitalize()

  # This should use the local indices eventually
  def blocked?({:profile, a}, clump_id), do: Baobab.ClumpMeta.blocked?(a, clump_id)
  def blocked?({a, _, _}, clump_id), do: Baobab.ClumpMeta.blocked?(a, clump_id)
  def blocked?(_, _), do: false

  def about_key(dude, key) do
    case :ets.lookup(:about, dude) do
      [{_, vals}] -> Map.get(vals, key, "")
      _ -> ""
    end
  end

  def checkbox_expander(boxes, name) do
    # Phoenix must be able to combine fieldsets and
    # yet here we are
    boxes
    |> Map.to_list()
    |> Enum.reduce([], fn {k, v}, a ->
      r = String.split(k, name)

      case Enum.at(r, 1) == v do
        true -> [v | a]
        false -> a
      end
    end)
  end
end
