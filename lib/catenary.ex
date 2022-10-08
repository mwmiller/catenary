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

  def short_id(id) do
    dets_open(:aliases)

    string =
      case :dets.lookup(:aliases, id) do
        [{^id, ali}] -> ali
        _ -> String.slice(id, 0..15)
      end

    dets_close(:aliases)

    "~" <> string
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
    [a, l, e] = string |> String.split("⋀")
    {a, String.to_integer(l), String.to_integer(e)}
  end

  def linked_author({a, _, _}), do: linked_author(a)

  def linked_author(a) do
    Phoenix.HTML.raw(
      "<abbr title=\"" <>
        a <>
        "\"><a class=\"author\" href=\"/entries/" <>
        index_to_string({a, -1, 0}) <> "\">" <> short_id(a) <> "</a></abbr>"
    )
  end

  def entry_icon_link({a, _, _} = entry, size) do
    "<button value=\"" <>
      Catenary.index_to_string(entry) <>
      "\" phx-click=\"view-entry\"><img " <>
      maybe_border(entry) <>
      " src=\"" <>
      Catenary.identicon(a, size) <>
      "\" title=\"" <> entry_title(entry) <> "\"\></button>"
  end

  defp entry_title({a, l, e}) do
    Enum.join(
      [
        Catenary.Quagga.pretty_log_name(l),
        "entry",
        Integer.to_string(e),
        "from",
        Catenary.short_id(a)
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
end
