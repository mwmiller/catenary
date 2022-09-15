defmodule Catenary do
  @moduledoc """
  Catenary keeps the contexts that define your domain
  and business logic.
  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """
  @dets_tables %{aliases: "aliases.dets", refs: "references.dets", prefs: "preferences.dets"}

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

  def identicon(id, type, mag \\ 4) do
    b64 = Excon.ident(id, base64: true, type: type, magnification: mag)

    mime =
      case type do
        :png -> "image/png"
        :svg -> "image/svg+xml"
      end

    "data:" <> mime <> ";base64," <> b64
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
      "<button phx-click=\"view-entry\" value=\"" <>
        index_to_string({a, 0, 0}) <> "\">" <> short_id(a) <> "</button>"
    )
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
