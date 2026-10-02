defmodule Catenary.IndexWorker.IndicaTest do
  use ExUnit.Case, async: true

  # Every index worker. A new one that forgets to declare `indica/0` cannot
  # get through here, which is the point: the strip shows a pill for each.
  @workers [
    Catenary.IndexWorker.About,
    Catenary.IndexWorker.Aliases,
    Catenary.IndexWorker.Listings,
    Catenary.IndexWorker.Challenges,
    Catenary.IndexWorker.Graph,
    Catenary.IndexWorker.Images,
    Catenary.IndexWorker.Mentions,
    Catenary.IndexWorker.Oases,
    Catenary.IndexWorker.Reactions,
    Catenary.IndexWorker.References,
    Catenary.IndexWorker.Tags,
    Catenary.IndexWorker.Timelines
  ]

  # The explorebar's view buttons. `unshown` has a button but no index
  # behind it, so nothing rests on `◎` — and nothing else may either, or
  # two buttons in the same bar would read as one.
  @buttons %{
    challenges: "⚄",
    listings: "⬡",
    tags: "#",
    images: "▣",
    reactions: "♥",
    unshown: "◎",
    aliases: "~",
    oases: "⇆"
  }

  @worker_views %{
    Catenary.IndexWorker.Challenges => :challenges,
    Catenary.IndexWorker.Listings => :listings,
    Catenary.IndexWorker.Tags => :tags,
    Catenary.IndexWorker.Images => :images,
    Catenary.IndexWorker.Reactions => :reactions,
    Catenary.IndexWorker.Aliases => :aliases,
    Catenary.IndexWorker.Oases => :oases
  }

  test "every worker reports a `{running, idle}` pair" do
    for worker <- @workers do
      assert {running, idle} = worker.indica()
      assert is_binary(running) and is_binary(idle)
      assert running != idle, "#{inspect(worker)} shows one glyph for both states"
    end
  end

  test "no two workers share a glyph" do
    glyphs = Enum.flat_map(@workers, &Tuple.to_list(&1.indica()))

    assert length(glyphs) == length(Enum.uniq(glyphs)),
           "two pills in the strip would be indistinguishable: #{inspect(glyphs)}"
  end

  test "a view-backed worker rests on the explorebar's own button glyph" do
    for {worker, view} <- @worker_views do
      {_running, idle} = worker.indica()
      button = Map.fetch!(@buttons, view)

      assert idle == button,
             "#{inspect(worker)} rests on #{idle}, but its #{view} button shows #{button}"
    end
  end

  test "no worker claims a foreign explorebar button's glyph" do
    for worker <- @workers,
        glyph <- Tuple.to_list(worker.indica()),
        {other_view, other} <- @buttons,
        other_view != Map.get(@worker_views, worker) do
      refute glyph == other,
             "#{inspect(worker)} uses #{glyph}, which is the #{other_view} button's glyph"
    end
  end
end
