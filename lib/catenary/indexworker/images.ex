defmodule Catenary.IndexWorker.Images do
  # This attribute is unused in local code.  It is maintained here
  # in case I change the compliation to not require duplication
  # @name_atom :images
  use Catenary.IndexWorker.Common,
    name_atom: :images,
    indica: {"𐍊", "҂"},
    logs: Enum.reduce(Catenary.image_logs(), [], fn n, a -> a ++ QuaggaDef.logs_for_name(n) end)

  @moduledoc """
  Write clump logged images to the file system
  """

  def do_index(todo, clump_id) do
    write_if_missing(todo, clump_id, Path.join(["priv", "static"]), %{})
  end

  defp write_if_missing([], _, _, acc), do: :ets.insert(:images, {:map, acc})

  defp write_if_missing([{_, _, seq} = entry | rest], clump_id, img_root, acc) do
    write_if_missing(
      rest,
      clump_id,
      img_root,
      fill_missing(
        Enum.to_list(1..seq),
        entry,
        clump_id,
        img_root,
        acc
      )
    )
  end

  defp fill_missing([], _, _, _, acc), do: acc

  defp fill_missing([seq | rest], {who, log_id, _} = last, clump_id, img_root, acc) do
    entry = {who, log_id, seq}
    src = Catenary.image_src_for_entry(entry, clump_id)
    filename = Path.join([img_root, src])

    this =
      case File.stat(filename) do
        {:ok, _} ->
          {src, entry}

        {:error, _} ->
          case Baobab.log_entry(who, seq, log_id: log_id, clump_id: clump_id) do
            %Baobab.Entry{payload: data} ->
              # Extra work here, but should be cheap.
              File.mkdir_p(Path.dirname(filename))
              File.write(filename, data, [:binary])
              {src, entry}

            _ ->
              {}
          end
      end

    fill_missing(rest, last, clump_id, img_root, accumulate_entries(this, acc))
  end

  defp accumulate_entries({src, {who, _, _} = entry} = full, acc) do
    ss =
      case Preferences.shown?(entry) do
        true -> :shown
        false -> :unshown
      end

    acc
    |> tiered_insert(:any, "any", full)
    |> tiered_insert(:shown, ss, full)
    |> tiered_insert(:type, Path.extname(src), full)
    |> tiered_insert(:poster, who, full)
  end

  defp accumulate_entries(_, acc), do: acc

  defp tiered_insert(map, first_tier, second_tier, val) do
    map
    |> Map.update(first_tier, %{second_tier => [val]}, fn inner_map ->
      Map.update(inner_map, second_tier, [val], fn list -> [val | list] end)
    end)
  end
end
