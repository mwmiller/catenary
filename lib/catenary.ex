defmodule Catenary do
  @moduledoc """
  Catenary keeps the contexts that define your domain
  and business logic.
  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """
  def short_id(id) do
    filename =
      Path.join([
        Application.get_env(:catenary, :application_dir, "~/.catenary"),
        "aliases.dets"
      ])
      |> Path.expand()
      |> to_charlist

    :dets.open_file(:aliases, file: filename)

    string =
      case :dets.lookup(:aliases, id) do
        [{^id, ali}] -> ali
        _ -> String.slice(id, 0..15)
      end

    :dets.close(:aliases)

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
end
