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
  def scaled_avatar(id, mag, classes \\ [])
  def scaled_avatar(nil, _mag, _classes), do: {:safe, ""}

  def scaled_avatar(id, mag, classes) do
    ss = Integer.to_string(mag * 8)
    all_classes = Enum.join(["rounded-full" | classes], " ")

    uri =
      case :ets.lookup(:avatars, id) do
        [{^id, {a, l, e, cid}}] ->
          p = Catenary.image_src_for_entry({a, l, e}, cid)
          :ets.insert(:avatars, {id, p})
          p

        [{^id, v}] when is_binary(v) ->
          path =
            v
            |> String.trim_leading("/cat_images")
            |> then(&Path.join(Catenary.images_dir(), &1))

          case File.exists?(path) do
            true ->
              v

            false ->
              :ets.delete(:avatars, id)
              write_svg_identicon(id, mag)
          end

        [{^id, v}] ->
          v

        [] ->
          val = write_svg_identicon(id, mag)

          :ets.insert(:avatars, {id, val})
          val
      end

    alt = short_id(id)

    Phoenix.HTML.raw(
      "<img alt=\"" <>
        alt <>
        "\" class=\"" <>
        all_classes <>
        "\" style=\"width:" <> ss <> "px;height:" <> ss <> "px;object-fit:cover\" src=\"" <> uri <> "\">"
    )
  end

  defp write_svg_identicon(id, mag) do
    idd = Path.join(["/cat_images", "identicons"])
    srv = Path.join([idd, id])
    file = Path.join([Catenary.images_dir(), "identicons", id <> ".svg"])
    Excon.ident(id, type: :framed, magnification: mag, filename: file)
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
    case QuaggaDef.log_def(log_id) do
      %{name: n} -> entry_title(n, data)
      _ -> entry_title(QuaggaDef.family_for_block(log_id), data)
    end
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
  defp faux_title(:challenge, %{"type" => "challenge"}), do: "Backgammon Challenge"
  defp faux_title(:challenge, %{"type" => "accept"}), do: "Challenge Accepted"
  defp faux_title(:challenge, %{"type" => "withdraw"}), do: "Challenge Withdrawn"
  defp faux_title(:challenge, _), do: "Challenge Log Entry"

  defp faux_title(:backgammon, %{"type" => "roll", "player" => p}),
    do: "Roll: " <> pretty_player(p)

  defp faux_title(:backgammon, %{"type" => "turn", "player" => p, "turn" => t}),
    do: "Turn " <> to_string(t) <> ": " <> pretty_player(p)

  defp faux_title(:backgammon, %{"type" => "turn", "player" => p}),
    do: "Turn: " <> pretty_player(p)

  defp faux_title(:backgammon, %{"type" => "resign", "player" => p}),
    do: "Resign: " <> pretty_player(p)

  defp faux_title(:backgammon, _), do: "Backgammon"
  defp faux_title(_, _), do: "untitled"

  @doc """
  Render a game ID in its human display form: compact Base62 (43 chars),
  alphabetically consistent with identity keys.

  Accepts the canonical raw 32-byte binary (as carried in CBOR entries) or
  the lowercase-hex form (as used in index/UI strings). Returns `""` for
  anything else.
  """
  @spec pretty_game_id(binary()) :: String.t()
  def pretty_game_id(bin) when byte_size(bin) == 32, do: BaseX.Base62.encode(bin)

  def pretty_game_id(hex) when is_binary(hex) do
    case Base.decode16(hex, case: :lower) do
      {:ok, bin} -> pretty_game_id(bin)
      :error -> ""
    end
  end

  def pretty_game_id(_), do: ""
  defp wrap_added_title(title), do: "⸤" <> title <> "⸣"

  defp pretty_player(p) when is_binary(p) do
    case Catenary.id_for_key(p) do
      nil -> String.slice(p, 0, 12) <> "…"
      alias_name -> alias_name
    end
  end

  defp pretty_player(_), do: "unknown"

  # Let's not delve into why I hate using templates
  @doc """
  The standard button which indicates a log entry will be created.
  """
  def log_submit_button do
    ~s(<button phx-disable-with="𝄇" type="submit" title="Post to log" aria-label="Post to log" class="w-full rounded-md bg-amber-500 hover:bg-amber-400 active:bg-amber-600 dark:bg-amber-400 dark:hover:bg-amber-300 dark:active:bg-amber-500 text-white dark:text-slate-900 text-sm font-semibold px-4 py-1.5 shadow-sm transition-colors">➲</button>)
    |> Phoenix.HTML.raw()
  end

  @doc """
  Turn an integer log_id or atom into a "nice" string.
  """
  def pretty_log_name(log_id) when is_integer(log_id) do
    {base_log, _} = QuaggaDef.log_id_unpack(log_id)

    base_log
    |> QuaggaDef.log_def()
    |> Map.get(:name, :unknown)
    |> cap_atom_string
  end

  def pretty_log_name(family) when is_atom(family), do: cap_atom_string(family)

  @doc """
  Return all known log types with an array of {pretty_string, atom}
  """
  def all_pretty_log_pairs do
    QuaggaDef.log_defs()
    |> Enum.map(fn {_id, %{name: n}} -> {cap_atom_string(n), n} end)
  end

  defp cap_atom_string(a), do: a |> Atom.to_string() |> String.capitalize()
end
