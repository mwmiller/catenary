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

  @img_root Path.join(["priv", "static"])
  @img_cat Path.join([@img_root, "cat_images"])

  def do_index(todo, clump_id) do
    # I'm going to avoid the sync for deletion for now
    # I will handle that with a preference screen cache clear
    # Instead we write out all of the new stuff
    :ok = write_missing(todo, clump_id)
    # And then see what's on the disk
    clump_id
    |> scan_clump()
    |> accumulate_entries(%{})
    |> then(fn m -> :ets.insert(:images, {:map, m}) end)
  end

  def scan_clump(clump) do
    clump
    |> then(fn c -> Path.join([@img_cat, c, "**"]) end)
    |> Path.wildcard()
    |> Enum.map(fn p -> Path.relative_to(p, @img_cat) end)
    |> files_to_entries([])
  end

  defp files_to_entries([], acc), do: acc

  defp files_to_entries([file | rest], acc) do
    with [clump_id, author, log_id, file] <- file |> Path.relative_to(@img_cat) |> Path.split(),
         {l, ""} <- Integer.parse(log_id),
         {e, ""} <- file |> Path.rootname() |> Integer.parse() do
      entry = {author, l, e}

      files_to_entries(rest, [
        {Catenary.image_src_for_entry(entry, clump_id), {author, l, e}} | acc
      ])
    else
      _ ->
        files_to_entries(rest, acc)
    end
  end

  defp write_missing([], _), do: :ok

  defp write_missing([{_, _, seq} = entry | rest], clump_id) do
    entry |> fill_missing(clump_id, seq)

    write_missing(rest, clump_id)
  end

  defp fill_missing(_, _, 0), do: :ok

  defp fill_missing({who, log_id, _} = last, clump_id, seq) do
    entry = {who, log_id, seq}
    src = Catenary.image_src_for_entry(entry, clump_id)
    filename = Path.join([@img_root, src])

    case File.stat(filename) do
      {:error, _} ->
        case Baobab.log_entry(who, seq, log_id: log_id, clump_id: clump_id) do
          %Baobab.Entry{payload: data} ->
            # Extra work here, but should be cheap.
            File.mkdir_p(Path.dirname(filename))
            File.write(filename, data, [:binary])
            {src, entry}

          _ ->
            :ok
        end

      _ ->
        :ok
    end

    fill_missing(last, clump_id, seq - 1)
  end

  defp accumulate_entries([], acc), do: acc

  defp accumulate_entries([{src, {who, _, _}} = full | rest], acc) do
    acc
    |> tiered_insert(:filesize, size_group(src), full)
    |> tiered_insert(:type, Path.extname(src), full)
    |> tiered_insert(:poster, who, full)
    |> then(fn a -> accumulate_entries(rest, a) end)
  end

  defp tiered_insert(map, first_tier, second_tier, val) do
    map
    |> Map.update(first_tier, %{second_tier => [val]}, fn inner_map ->
      Map.update(inner_map, second_tier, [val], fn list -> [val | list] end)
    end)
  end

  defp size_group(filename) do
    # We have been dinking around enough
    # we should know they exist at this point
    # but racing!
    size =
      case File.stat(Path.join([@img_root, filename])) do
        {:ok, %{size: s}} -> s
        _ -> 0
      end

    cond do
      size < 100 * 1024 -> "tiny"
      size < 1 * 1024 * 1024 -> "small"
      size < 10 * 1024 * 1024 -> "med"
      true -> "huge"
    end
  end
end
