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
        assert Navigation.displayed_matches([unquote(desired)], unquote(displayed)) == unquote(expected)
      end
    end

    test "displayed_matches returns true if any desired view matches" do
      assert Navigation.displayed_matches([:log, :entries], :entries)
      refute Navigation.displayed_matches([:log], :entries)
    end
  end
end
