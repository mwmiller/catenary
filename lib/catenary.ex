defmodule Catenary do
  @moduledoc """
  Catenary keeps the contexts that define your domain
  and business logic.
  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """
  @dets_tables %{
    aliases: "aliases.dets",
    refs: "references.dets",
    prefs: "preferences.dets",
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
      |> Enum.reduce(%{}, fn [{a, n}], acc -> Map.put(acc, a, n) end)

    Catenary.dets_close(:aliases)
    {:ok, aliases}
  end

  def id_for_key(key), do: id_for_key(Baobab.identities(), key)
  def id_for_key([], key), do: {:error, "No such identity for key " <> key}
  def id_for_key([{ali, key} | _], key), do: ali
  def id_for_key([_ | rest], key), do: id_for_key(rest, key)

  def identicon(id, mag \\ 4) do
    "data:image/svg+xml;base64," <> Excon.ident(id, base64: true, type: :svg, magnification: mag)
  end

  def index_to_string(tuple) do
    tuple |> Tuple.to_list() |> Enum.map(fn e -> to_string(e) end) |> Enum.join("⋀")
  end

  def string_to_index(string) do
    # We assume all psuedo-entries are two-element tagged
    # All three elements are "real" indices.
    case String.split(string, "⋀") do
      [a, l, e] -> {a, String.to_integer(l), String.to_integer(e)}
      [t, w] -> {String.to_existing_atom(t), w}
    end
  end

  def linked_author({a, _, _}, aliases), do: linked_author(a, aliases)

  def linked_author(a, aliases) do
    view_entry_button({:profile, a}, short_id(a, aliases)) |> Phoenix.HTML.raw()
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

  @timeline_logs [:journal, :reply, :tag, :alias]
  def timeline_logs, do: @timeline_logs
  def random_timeline_log(), do: @timeline_logs |> Enum.random()

  def pretty_log_name(log_id) do
    case QuaggaDef.log_id_unpack(log_id) do
      {base_log, _} ->
        base_log
        |> QuaggaDef.log_def()
        |> Map.get(:name, :unknown)
        |> Atom.to_string()
        |> String.capitalize()

      _ ->
        ""
    end
  end
end
