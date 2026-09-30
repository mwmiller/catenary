defmodule CatenaryWeb.Live.NavigationTest do
  use ExUnit.Case, async: true

  alias Catenary.Live.Navigation

  describe "displayed_matches/2" do
    # Truth table: the second element is the currently displayed view state,
    # which may be a bare view atom or a tagged tuple {:log|:pseudo|:view, inner}.
    # The first element is the desired view we are checking membership for.
    where = [
      # desired, displayed, expected
      {:log, :log, true},
      {:log, {:log, :log}, true},
      {:log, {:pseudo, :log}, false},
      {:log, :entries, false},
      {:entries, {:log, :entries}, true},
      {:entries, {:pseudo, :entries}, true},
      {:entries, {:view, :entries}, true},
      {:entries, :entries, true},
      {:pseudo, {:pseudo, :x}, true},
      {:pseudo, {:log, :pseudo}, false},
      {:view, {:view, :x}, true},
      {:entries, {:tag, "t"}, false},
      {:profile, :entries, false}
    ]

    for {desired, displayed, expected} <- where do
      test "displayed_matches(#{inspect(desired)}, #{inspect(displayed)}) == #{inspect(expected)}" do
        assert Navigation.displayed_matches([unquote(desired)], unquote(displayed)) ==
                 unquote(expected)
      end
    end

    test "displayed_matches returns true if any desired view matches" do
      assert Navigation.displayed_matches([:log, :entries], :entries)
      refute Navigation.displayed_matches([:log], :entries)
    end
  end

  describe "available_extra_nav/2" do
    # Every rule below mirrors a trigger in Navigation's render/1: a panel may
    # only stay open where the button that opened it still exists.
    test "a panel the current screen has no trigger for resolves to :none" do
      # reply/react/tag/mention are only offered on a log entry.
      assert Navigation.available_extra_nav(:reply, {:view, :tags}) == :none
      assert Navigation.available_extra_nav(:react, {:unknown, :unknown}) == :none
      assert Navigation.available_extra_nav(:tag, {:pseudo, :tag}) == :none

      # alias/block need a log entry or a profile; a bare tag is neither.
      assert Navigation.available_extra_nav(:alias, {:pseudo, :tag}) == :none
      assert Navigation.available_extra_nav(:graph, {:view, :prefs}) == :none

      # The avatar panel is forced by viewing an image, and only then.
      assert Navigation.available_extra_nav(:image_avatar, {:log, :journal}) == :none

      # Anything with no panel at all, and a panel that is already shut.
      assert Navigation.available_extra_nav(:not_a_panel, {:log, :journal}) == :none
      assert Navigation.available_extra_nav(:none, {:log, :journal}) == :none
    end

    test "panels without a view restriction of their own stay offered" do
      assert Navigation.available_extra_nav(:challenge, {:unknown, :unknown}) == :challenge
      assert Navigation.available_extra_nav(:profile, {:view, :tags}) == :profile
      assert Navigation.available_extra_nav(:image_avatar, {:log, :jpeg}) == :image_avatar
    end
  end

  describe "resolve_extra_nav/3" do
    test "derives the screen from the view and entry itself" do
      # The tags screen is not a log entry, so it cannot carry a reply panel.
      assert Navigation.resolve_extra_nav(:reply, :tags, :all) == :none
      assert Navigation.resolve_extra_nav(:none, :entries, :all) == :none
      assert Navigation.resolve_extra_nav(:challenge, :entries, :all) == :challenge
    end
  end
end
