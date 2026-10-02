defmodule Catenary.IndicesTest do
  use ExUnit.Case, async: false

  # The canonical strip order, mirroring the explorebar: `about` anchors the
  # left end beside the identity cluster, then every view-backed index in
  # its button's left-to-right order, then the indices with no view of
  # their own. Kept here rather than in the moduledoc so a reorder has to
  # be a deliberate edit in two places.
  @order [
    :about,
    :challenges,
    :listings,
    :tags,
    :images,
    :reactions,
    :aliases,
    :oases,
    :graph,
    :references,
    :timelines,
    :mentions
  ]

  test "every index in the canonical order has a running worker" do
    for which <- @order do
      assert is_pid(GenServer.whereis(which)), "#{which} is listed but no worker answers for it"
    end
  end

  test "the status strip reads in the canonical order" do
    listed = Catenary.Indices.status() |> Keyword.keys()

    # Subsequence check first: a worker that has not reported yet must not
    # look like an ordering bug. Then require the full set, so a worker
    # that never reports is caught rather than quietly dropped.
    assert listed == Enum.filter(@order, &(&1 in listed))
    assert length(listed) == length(@order)
  end
end
