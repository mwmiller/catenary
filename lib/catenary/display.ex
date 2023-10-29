defmodule Catenary.Display do
  @moduledoc """
  Display formatting functions used across contexts.
  """

  @doc """
  Get the displayable short id string

  This is wildly inefficient at present if the alias_state is not supplied.
  """
  def short_id(id, alias_state \\ nil)
  def short_id(id, nil), do: short_id(id, Catenary.alias_state())

  def short_id(id, {_, aliases}) do
    string =
      case Map.get(aliases, id) do
        nil -> String.slice(id, 0..10)
        ali -> ali
      end

    "~" <> string
  end

  @doc """
  Emit an avatar scaled and styled per parameters
  """
  def scaled_avatar(id, mag, classes \\ []) do
    ss = Integer.to_string(mag * 8)

    uri =
      case :ets.lookup(:avatars, id) do
        [{^id, {a, l, e, cid}}] ->
          p = Catenary.image_src_for_entry({a, l, e}, cid)
          :ets.insert(:avatars, {id, p})
          p

        [{^id, v}] ->
          v

        [] ->
          val = write_svg_identicon(id, mag)

          :ets.insert(:avatars, {id, val})
          val
      end

    Phoenix.HTML.raw(
      "<img class=\"" <>
        Enum.join(classes, " ") <>
        "\"  width=" <> ss <> " height=" <> ss <> " src=\"" <> uri <> "\">"
    )
  end

  defp write_svg_identicon(id, mag) do
    fs = Path.join([Application.app_dir(:catenary), "priv", "static"])
    idd = Path.join(["/cat_images", "identicons"])
    srv = Path.join([idd, id])
    file = Path.join([fs, srv])
    Excon.ident(id, type: :svg, magnification: mag, filename: file)
    srv <> ".svg"
  end

  @doc """
  Emit a link to an author profile
  """
  def linked_author(author, aliases, type \\ :button)
  def linked_author({a, _, _}, aliases, type), do: linked_author(a, aliases, type)

  def linked_author(a, aliases, :button) do
    view_entry_button({:profile, a}, short_id(a, aliases)) |> Phoenix.HTML.raw()
  end

  def linked_author(a, aliases, :href) do
    Phoenix.HTML.raw("<a href=\"/authors/" <> a <> "\">" <> short_id(a, aliases) <> "</a>")
  end

  @doc """
  Emit a link to a particular entry
  """
  def view_entry_button(entry, {:safe, contents}), do: view_entry_button(entry, contents)

  def view_entry_button(entry, contents) do
    "<button value=\"" <>
      Catenary.index_to_string(entry) <>
      "\" phx-click=\"view-entry\">" <> contents <> "</button>"
  end

  @doc """
  Emit a link to a particular entry with an author avatar attached
  """
  def avatar_view_entry_button({a, _, _} = entry, contents) do
    {:safe, ava} = scaled_avatar(a, 1, ["m-1", "float-left", "align-middle"])
    ava <> view_entry_button(entry, contents)
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

  @doc """
  Extract or create a title for given entry data
  """
  def entry_title(log_id, data) when is_integer(log_id) do
    %{name: n} = QuaggaDef.log_def(log_id)
    entry_title(n, data)
  end

  @image_logs Catenary.image_logs()

  def entry_title(type, data) when type in @image_logs, do: entry_title(:image, data)
  def entry_title(_type, %{"title" => ""}), do: wrap_added_title("untitled")
  def entry_title(_type, %{"title" => title}), do: title
  def entry_title(type, data), do: added_title(type, data)

  defp added_title(type, data), do: type |> faux_title(data) |> wrap_added_title
  defp faux_title(:test, _), do: "Test Post"
  defp faux_title(:image, _), do: "Image Upload"
  defp faux_title(:alias, %{"alias" => ali}), do: "Alias: ~" <> ali
  defp faux_title(:about, _), do: "Profile Update"
  defp faux_title(:mention, _), do: "Mention"
  defp faux_title(:graph, %{"action" => act}), do: String.capitalize(act)
  defp faux_title(:react, _), do: "Reaction"
  defp faux_title(:oasis, %{"name" => name}), do: "Oasis: " <> name
  defp faux_title(:tag, _), do: "Tagging"
  defp faux_title(_, _), do: "untitled"
  defp wrap_added_title(title), do: "⸤" <> title <> "⸣"

  # Let's not delve into why I hate using templates
  @doc """
  The standard button which indicates a log entry will be created.
  """
  def log_submit_button do
    """
    <hr/>
    <button phx-disable-with="𝄇" type="submit">➲</button>
    """
    |> Phoenix.HTML.raw()
  end

  @doc """
  Turn an integer log_id into a "nice" string.
  """
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

  @doc """
  Wrap Explorer items
  """
  def explore_wrap(which) do
    ("<div id=\"" <>
       which <>
       "-explore-wrap\" class=\"col-span-2 overflow-y-auto max-h-screen m-2 p-x-2\">" <>
       "<h1>" <> String.capitalize(which) <> " Explorer</h1><hr/>")
    |> Phoenix.HTML.raw()
  end

  @doc """
  Return all known log types with an array of {pretty_string, atom}
  """
  def all_pretty_log_pairs() do
    QuaggaDef.log_defs()
    |> Enum.map(fn {_id, %{name: n}} -> {cap_atom_string(n), n} end)
  end

  defp cap_atom_string(a), do: a |> Atom.to_string() |> String.capitalize()
end
