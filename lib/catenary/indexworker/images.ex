defmodule Catenary.IndexWorker.Images do
  # This attribute is unused in local code.  It is maintained here
  # in case I change the compliation to not require duplication
  # @name_atom :images
  use Catenary.IndexWorker.Common, name_atom: :images, indica: {"𐍊", "҂"}

  @moduledoc """
  Write clump logged images to the file system
  """

  def update_from_logs(inform \\ []) do
    clump_id = Preferences.get(:clump_id)
    logs = Enum.reduce(Catenary.image_logs(), [], fn n, a -> a ++ QuaggaDef.logs_for_name(n) end)

    clump_id
    |> Baobab.stored_info()
    |> Enum.reduce([], fn {a, l, e}, acc ->
      case l in logs do
        false -> acc
        true -> [{a, l, e} | acc]
      end
    end)
    |> write_if_missing(clump_id, Path.join(["priv", "static"]), %{})

    run_complete(inform, self())
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
          end

        _ ->
          {}
      end

    fill_missing(rest, last, clump_id, img_root, accumulate_entries(this, acc))
  end

  defp accumulate_entries({src, {who, _, _}} = full, acc) do
    acc
    |> tiered_insert(:any, "any", full)
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
