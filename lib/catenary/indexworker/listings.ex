defmodule Catenary.IndexWorker.Listings do
  @name_atom :listings

  use Catenary.IndexWorker.Common,
    name_atom: :listings,
    indica: {"⬢", "⬡"},
    logs: Catenary.Apps.listing_logs()

  @moduledoc """
  Listings index.

  Scans the listings control log (`Catenary.Apps.listing_logs/0`: log 2777
  across its facets) and keeps one row per `(pk, slug)` it currently
  announces. The artifact kind log is deliberately *not* scanned — the row
  carries the release's metadata and the hash its bytes must have, and
  resolves to content only when a viewer asks for it.

  The log carries listings for every family the control log announces, not
  just apps: `family` decides which family a row belongs to, so a second
  family landing on the control log is indexed here alongside the first.

  An entry is the release record folded into its announcement:

      %{"type" => "listing", "family" => 2, "slug" => "example-app",
        "version" => "1.2.3", "abi" => "catenary_v1", "features" => [],
        "artifact" => <<...32 bytes...>>, "description" => "a tiny app",
        "published" => iso8601}

  `family` is the one field that decides which family a row belongs to; the
  signing key, the data-channel base and the kind sub-ids are all recomputed
  from `{pk, slug}` by whoever reads them, so an entry cannot smuggle in a
  second, conflicting answer for them. `version` is the declared release
  version; a listing written before the fold carried an integer `v` instead
  (its manifest's sequence number), and a row keeps whichever it found.

  `description` is optional and unvalidated — the log is written by anyone —
  so it is stored as text or not at all, and a row without one still lists.
  How much of it a view shows is the view's business.

  `"type" => "delist"` removes the row. Whatever sits at the head of the log
  wins, so a re-listing after a delisting puts the row back.

  The whole listing set is rebuilt on every pass rather than folded
  incrementally: entries are few, and a rebuild is the only shape that
  cannot be left stale by a cross-facet race or by the store still being
  cold when the worker first loads.
  """

  alias Catenary.Apps

  # The tags this control log announces. A row has to name one of them, so
  # entries claiming anything else are dropped rather than stored under a
  # name the control log never vouched for.
  @listed_families Enum.map(QuaggaDef.families_for_control_log(:listing), fn {_name, tag} ->
                     tag
                   end)

  def do_index(_todo, clump_id, _prev_seen) do
    clump_id
    |> Baobab.stored_info()
    |> Enum.filter(fn {_a, l, _e} -> l in @logs_of_interest end)
    |> Enum.sort_by(fn {a, l, _} -> {a, l} end)
    |> Enum.reduce(%{}, fn {a, l, _}, listings -> fold_log(a, l, clump_id, listings) end)
    |> publish()

    # The log-seqnum map that `updated_logs/3` builds is the whole of the
    # incremental state this worker needs; nothing here is keyed by anything
    # it does not already track.
    %{}
  end

  # Oldest first within a log, ascending `{author, log_id}` across logs, so
  # the last entry written for a slug is the one that survives the fold.
  defp fold_log(a, l, clump_id, listings) do
    a
    |> Baobab.full_log(log_id: l, clump_id: clump_id)
    |> Enum.reduce(listings, &fold_entry(&1, l, &2))
  end

  defp fold_entry(%Baobab.Entry{author: author, payload: payload, seqnum: seqnum}, l, listings) do
    with {:ok, data, ""} <- CBOR.decode(payload),
         family when family in @listed_families <- data["family"],
         slug when is_binary(slug) <- data["slug"],
         true <- Apps.valid_slug?(slug) do
      put_entry(data, Baobab.Identity.as_base62(author), slug, family, l, seqnum, listings)
    else
      _ -> listings
    end
  end

  defp put_entry(%{"type" => "listing"} = data, pk, slug, family, l, seqnum, listings) do
    case version_of(data) do
      nil ->
        listings

      version ->
        Map.put(listings, {pk, slug}, %{
          pk: pk,
          slug: slug,
          family: family,
          version: version,
          description: Apps.description(data),
          published: data["published"],
          log_id: l,
          seqnum: seqnum
        })
    end
  end

  defp put_entry(%{"type" => "delist"}, pk, slug, _family, _l, _seqnum, listings),
    do: Map.delete(listings, {pk, slug})

  defp put_entry(_data, _pk, _slug, _family, _l, _seqnum, listings), do: listings

  # The label a row shows: the declared release version, or — for a
  # listing written before the fold — the integer `v` that pointed at its
  # manifest. A listing with neither is not an announcement this index can
  # vouch for, and is dropped with the other junk.
  defp version_of(%{"version" => version}) when is_binary(version), do: version
  defp version_of(%{"v" => v}) when is_integer(v), do: v
  defp version_of(_data), do: nil

  # Swap the snapshot wholesale: insert the new rows, publish them as the
  # one `:display` list, then drop whatever the fold no longer vouches for.
  # Doing it in that order means the explorer never reads a hole where a
  # just-removed listing used to be.
  defp publish(listings) do
    :ets.insert(@name_atom, Map.to_list(listings))

    display =
      listings
      |> Map.values()
      |> Enum.sort_by(&{&1.family, &1.slug})

    :ets.insert(@name_atom, {:display, display})

    @name_atom
    |> :ets.tab2list()
    |> Enum.map(&elem(&1, 0))
    |> Enum.reject(&(&1 == :display or Map.has_key?(listings, &1)))
    |> Enum.each(&:ets.delete(@name_atom, &1))

    :ok
  end
end
