defmodule Catenary do
  @moduledoc """
  Catenary keeps the contexts that define your domain
  and business logic.
  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """
  @dets_tables %{prefs: "preferences.dets"}

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

  def mime_for_entry({_, l, _}) do
    %{name: mime} = l |> QuaggaDef.base_log() |> QuaggaDef.log_def()
    mime
  end

  def ext_for_entry(entry), do: entry |> mime_for_entry |> Atom.to_string()

  def image_src_for_entry({a, l, e} = entry, clump_id) do
    Path.join([
      "/cat_images",
      clump_id,
      a,
      Integer.to_string(l),
      Integer.to_string(e) <>
        "." <> ext_for_entry(entry)
    ])
  end

  def alias_state(), do: {:ok, Catenary.State.get(:aliases)}

  def profile_items_state(), do: {:ok, Catenary.State.get(:profile)}

  def oasis_state(clump_id) do
    # For now I am going to recreate the sorted by
    # recency experience. I don't expect it to persist
    oasis_items =
      case :ets.lookup(:oases, clump_id) do
        [] -> %{}
        [{^clump_id, items}] -> items
      end
      |> Map.values()
      |> Enum.sort_by(fn m -> Map.get(m, "running") end, :desc)
      |> Enum.map(fn m -> Map.put(m, :connected, Baby.is_connected?({m["host"], m["port"]})) end)

    {:ok, oasis_items}
  end

  def id_for_key(key), do: find_id_for_key(Baobab.Identity.list(), key)
  defp find_id_for_key([], key), do: {:error, "No identity found for key " <> key}
  defp find_id_for_key([{ali, key} | _], key), do: ali
  defp find_id_for_key([_ | rest], key), do: find_id_for_key(rest, key)

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

  def clump_stats(clump_id) do
    clump_id
    |> Baobab.stored_info()
    |> Enum.reduce({{0, 0, 0}, MapSet.new()}, fn {a, _, e}, {{ac, lc, pc}, as} ->
      author_inc =
        case MapSet.member?(as, a) do
          true -> 0
          false -> 1
        end

      {{ac + author_inc, lc + 1, pc + e}, MapSet.put(as, a)}
    end)
    |> then(fn {counts, _} -> counts end)
  end
end
