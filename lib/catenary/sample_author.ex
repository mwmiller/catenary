defmodule Catenary.SampleAuthor do
  @moduledoc """
  The canned store fixture the playground's data-source picker points a
  run at: an identity that exists so a module has somebody's timeline and
  profile to read before the author has written anything of their own.

  The first pick creates the identity — a fresh key on this device, never
  a shared account — and writes the entries every later pick expects:
  three journal posts and a profile. Later picks cost one lookup and
  append nothing, so the fixture stays where it was rather than growing a
  post every time the panel is opened. A name the store already holds is
  used as it stands: the fixture never overwrites a key, not even this
  name's.

  Entries land on the current facet's logs like any other write, and the
  indices the reads go through are run synchronously before this returns,
  so the first read after a pick sees the entries without waiting on a
  worker race. What the fixture never does is sign or publish: a run
  pointed here *reads* this identity's data while its own publishes still
  land on its own channel under its own key (§6).
  """

  @name "sample-author"

  # Oldest first, which is the order they are appended in: the newest post
  # is the last one written and the head of any timeline page. The days
  # they are dated apart are what makes the order legible in a feed rather
  # than three entries stamped in the same second.
  @journal [
    {"Hello from the fixture",
     "The store fixture picker wrote this so a run pointed at sample data " <>
       "has a timeline to read."},
    {"What this identity is",
     "sample-author is canned data. Nobody is signed in as this key; the " <>
       "entries exist to be read."},
    {"Three posts, so paging has a reason",
     "A page of two skips the oldest of these, which is what a cursor is for."}
  ]

  @description "Canned profile data the fixture picker writes on first use."

  @doc """
  Make sure the sample identity exists with its seeded entries, and
  return the key reads should name.

  `clump_id` and `facet_id` are the run's own: the fixture writes where
  the rest of the store is writing, on the facet everything else is
  indexed under.
  """
  @spec ensure(String.t(), 0..255) :: {:ok, binary} | {:error, String.t()}
  def ensure(clump_id, facet_id)
      when is_binary(clump_id) and is_integer(facet_id) and facet_id in 0..255 do
    with {:ok, pk} <- identity(),
         {:ok, seeded} <- seed(pk, clump_id, facet_id) do
      reindex(seeded)
      {:ok, pk}
    end
  end

  # Absent from the store is create; present is use-as-it-stands, which is
  # why this never writes over an existing name. `create/1` answers with
  # the bare key while a lookup carries it, so both are tagged here and
  # callers see one shape either way.
  defp identity do
    case List.keyfind(Baobab.Identity.list(), @name, 0) do
      {_name, pk} -> {:ok, pk}
      nil -> created(Baobab.Identity.create(@name))
    end
  end

  defp created(pk) when is_binary(pk), do: {:ok, pk}
  defp created({:error, _} = refused), do: refused

  # Each log is seeded only while it is empty: an entry somebody else
  # wrote is theirs, and a second pick appends nothing. The returned index
  # names are the ones whose rows the reads consult.
  defp seed(pk, clump_id, facet_id) do
    jobs = [
      {:timelines, QuaggaDef.facet_log(:journal, facet_id), &journal/0},
      {:about, QuaggaDef.facet_log(:about, facet_id), &profile/0}
    ]

    seeded =
      Enum.reduce(jobs, [], fn job, acc ->
        case seed_log(pk, clump_id, job) do
          {:ok, index} -> [index | acc]
          :quiet -> acc
        end
      end)

    {:ok, seeded}
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp seed_log(pk, clump_id, {index, log_id, entries}) do
    if empty?(pk, log_id, clump_id) do
      Enum.each(entries.(), fn entry ->
        Baobab.append_log(CBOR.encode(entry), @name,
          log_id: log_id,
          clump_id: clump_id
        )
      end)

      {:ok, index}
    else
      :quiet
    end
  end

  defp empty?(pk, log_id, clump_id),
    do: Baobab.max_seqnum(pk, log_id: log_id, clump_id: clump_id) == 0

  # The same payload shape `Catenary.LogWriter` writes for a journal post
  # and a profile update, so the indices fold these exactly as they fold
  # anything else: nothing here is special-cased downstream.
  defp journal do
    now = DateTime.utc_now()
    count = length(@journal)

    @journal
    |> Enum.with_index(1)
    |> Enum.map(fn {{title, body}, seq} ->
      %{
        "title" => title,
        "body" => body,
        "published" => now |> DateTime.add(seq - count, :day) |> DateTime.to_string()
      }
    end)
  end

  defp profile do
    [
      %{
        "name" => "Sample Author",
        "description" => @description,
        "published" => DateTime.utc_now() |> DateTime.to_string()
      }
    ]
  end

  # Synchronous on purpose: the pick returns straight into a run, and a run
  # that reads before the worker's cast lands would find the empty store
  # and report the fixture broken. A worker not yet started indexes on its
  # own first pass instead, which is the same rows a moment later.
  defp reindex(indices) do
    Enum.each(indices, fn index ->
      case Process.whereis(index) do
        nil -> :ok
        _pid -> GenServer.call(index, :update)
      end
    end)
  end
end
