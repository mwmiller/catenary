defmodule Catenary.ImageWriter do
  require Logger

  @moduledoc """
  Write clump logs to the file system
  """

  def update_from_logs(clump_id, inform \\ nil) do
    logs = Enum.reduce(Catenary.image_logs(), [], fn n, a -> a ++ QuaggaDef.logs_for_name(n) end)

    ppid = self()

    Task.start(fn ->
      clump_id
      |> Baobab.stored_info()
      |> Enum.reduce([], fn {a, l, _}, acc ->
        case l in logs do
          false -> acc
          true -> [{a, l} | acc]
        end
      end)
      |> write_if_missing(clump_id, Path.join(["priv/static/cat_images", clump_id]))

      case inform do
        nil -> :ok
        pid -> Process.send(pid, {:completed, {:indexing, :images, ppid}}, [])
      end
    end)
  end

  defp write_if_missing([], _, _), do: :ok

  defp write_if_missing([{who, log_id} | rest], clump_id, img_root) do
    # We want these to be file system browsable, so they look like this
    img_dir = Path.join([img_root, who, Integer.to_string(log_id)]) |> Path.expand()
    max = Baobab.max_seqnum(who, log_id: log_id, clump_id: clump_id)
    # These may be missing because we haven't processed or because the
    # log is partially replicated
    missing = MapSet.new(1..max) |> MapSet.difference(extant_entries(img_dir)) |> MapSet.to_list()

    case missing do
      [] ->
        :ok

      todo ->
        # Extra work here, but should be cheap.
        File.mkdir_p(img_dir)
        fill_missing(todo, who, log_id, clump_id, img_dir)
    end

    write_if_missing(rest, clump_id, img_root)
  end

  # We don'd expact large numbers per log so we don't hash in more dirs
  defp extant_entries(img_dir) do
    Path.join(img_dir, "**")
    |> Path.wildcard()
    |> Enum.map(fn i -> i |> Path.basename() |> Path.rootname() |> String.to_integer() end)
    |> MapSet.new()
  end

  defp fill_missing([], _, _, _, _), do: :ok

  defp fill_missing([e | rest], who, log_id, clump_id, img_dir) do
    case Baobab.log_entry(who, e, log_id: log_id, clump_id: clump_id) do
      %Baobab.Entry{payload: data} ->
        %{name: mime} = log_id |> QuaggaDef.base_log() |> QuaggaDef.log_def()

        # I don't much care if this fails.  I mean I do, but I don't
        # have a solution.. and it might work next time
        File.write(
          Path.join([img_dir, Integer.to_string(e) <> "." <> Atom.to_string(mime)]),
          data,
          [:binary]
        )

      _ ->
        :ok
    end

    fill_missing(rest, who, log_id, clump_id, img_dir)
  end
end
