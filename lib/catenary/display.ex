defmodule Catenary.Display do
  @moduledoc """
  Display formatting functions used across contexts.
  """

  @doc """
  Extract or create a title for given entry data
  """
  def entry_title(log_id, data) when is_integer(log_id) do
    %{name: n} = QuaggaDef.log_def(log_id)
    entry_title(n, data)
  end

  def entry_title(type, data) when type in [:jpeg, :png, :gif], do: entry_title(:image, data)
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
  Return all known log types with an array of {pretty_string, atom}
  """
  def all_pretty_log_pairs() do
    QuaggaDef.log_defs()
    |> Enum.map(fn {_id, %{name: n}} -> {cap_atom_string(n), n} end)
  end

  defp cap_atom_string(a), do: a |> Atom.to_string() |> String.capitalize()
end
