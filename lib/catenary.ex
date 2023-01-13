defmodule Catenary do
  @moduledoc """
  Catenary keeps the contexts that define your domain
  and business logic.
  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """
  @dets_tables %{
    aliases: "aliases.dets",
    identicons: "identicons.dets",
    graph: "social_graph.dets",
    mentions: "mentions.dets",
    prefs: "preferences.dets",
    reactions: "reactions.dets",
    references: "references.dets",
    tags: "tags.dets",
    timelines: "timelines.dets"
  }

  def short_id(id, {_, aliases}) do
    string =
      case Map.get(aliases, id) do
        nil -> String.slice(id, 0..10)
        ali -> ali
      end

    "~" <> string
  end

  def alias_state() do
    dets_open(:aliases)

    Catenary.dets_open(:aliases)

    aliases =
      :dets.match(:aliases, :"$1")
      |> Enum.reject(fn [{a, _}] -> is_atom(a) end)
      |> Enum.reduce(%{}, fn [{a, n}], acc -> Map.put(acc, a, n) end)

    Catenary.dets_close(:aliases)
    {:ok, aliases}
  end

  def id_for_key(key), do: find_id_for_key(Baobab.Identity.list(), key)
  defp find_id_for_key([], key), do: {:error, "No identity found for key " <> key}
  defp find_id_for_key([{ali, key} | _], key), do: ali
  defp find_id_for_key([_ | rest], key), do: find_id_for_key(rest, key)

  def identicon(id, mag \\ 4) do
    dets_open(:identicons)
    k = {id, mag}

    idi =
      case :dets.lookup(:identicons, k) do
        [{^k, v}] ->
          v

        [] ->
          val =
            "data:image/svg+xml;base64," <>
              Excon.ident(id, base64: true, type: :svg, magnification: mag)

          :dets.insert(:identicons, {k, val})
          val
      end

    dets_close(:identicons)
    idi
  end

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

  defp view_entry_button(entry, contents) do
    "<button value=\"" <>
      Catenary.index_to_string(entry) <>
      "\" phx-click=\"view-entry\">" <> contents <> "</button>"
  end

  def entry_icon_link({a, _, _} = entry, size) do
    view_entry_button(
      entry,
      "<img " <>
        maybe_border(entry) <>
        " src=\"" <>
        Catenary.identicon(a, size) <>
        "\" title=\"" <> entry_title(entry) <> "\"\>"
    )
  end

  def entry_icon_link({:profile, a} = entry, size) do
    view_entry_button(
      entry,
      "<img " <>
        maybe_border(entry) <>
        " src=\"" <>
        Catenary.identicon(a, size) <>
        "\" title=\"profile\"\>"
    )
  end

  defp entry_title({_a, l, e}) do
    Enum.join(
      [
        pretty_log_name(l),
        "entry",
        Integer.to_string(e)
      ],
      " "
    )
  end

  def maybe_border(entry) do
    case Catenary.Preferences.shown?(entry) do
      true ->
        "class=\"mx-auto\""

      false ->
        "class=\"mx-auto new-border rounded \""
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
