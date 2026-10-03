defmodule Catenary.SampleAuthorFixture do
  @moduledoc """
  Takes back the sample author's store footprint: the identity, its two
  seeded logs and the index rows keyed under its key.

  The fixture is real store state — it outlives a test and a run of the
  suite — so any test that points something at it, or that would be
  disturbed by leftovers under the name, removes it on the way out the
  same way an app test purges the logs it wrote.
  """

  @name "sample-author"

  @spec purge() :: :ok
  def purge do
    clump_id = Catenary.Preferences.get(:clump_id)
    facet_id = Catenary.Preferences.get(:facet_id)

    case List.keyfind(Baobab.Identity.list(), @name, 0) do
      nil ->
        :ok

      {_, pk} ->
        for log_id <- [
              QuaggaDef.facet_log(:journal, facet_id),
              QuaggaDef.facet_log(:about, facet_id)
            ] do
          Baobab.purge(pk, log_id: log_id, clump_id: clump_id)
        end

        for table <- [:timelines, :about], :ets.whereis(table) != :undefined do
          :ets.delete(table, pk)
        end

        Baobab.Identity.drop(@name)
    end

    :ok
  end
end
