defmodule Catenary.NavigationTest do
  use ExUnit.Case, async: true

  alias Catenary.Navigation

  describe "move_to/3" do
    defp assigns do
      %{
        store: [],
        view: :entries,
        entry: {:profile, "a"},
        identity: "a",
        entry_back: [],
        entry_fore: []
      }
    end

    test "a 'specified' motion from :current that is already at the entry stays put" do
      result = Navigation.move_to("specified", :current, assigns())
      assert %{view: :entries, entry: {:profile, "a"}, entry_back: [], entry_fore: []} = result
      # No back entry is pushed when the destination equals the current state.
      assert result == %{view: :entries, entry: {:profile, "a"}, entry_back: [], entry_fore: []}
    end

    test "a 'specified' motion from a supplied state navigates and records history" do
      from = %{view: :entries, entry: {:profile, "a"}, entry_back: [], entry_fore: []}

      result =
        Navigation.move_to("specified", %{view: :tags, entry: {:tag, "t", 1}}, assigns())

      # entry_back is seeded with the supplied `from`; entry_fore cleared
      assert result.entry_back == [from]
      assert result.entry_fore == []
      assert result.entry == {:tag, "t", 1}
    end

    test "'back' with no history returns the supplied state unchanged" do
      sent = %{view: :profiles, entry: {:profile, "a"}, entry_back: [], entry_fore: []}
      result = Navigation.move_to("back", sent, assigns())
      assert result == sent
    end

    test "'back' pops the most recent history entry" do
      prev = %{view: :profiles, entry: {:profile, "z"}, entry_back: [], entry_fore: []}
      sent = %{view: :entries, entry: {:profile, "a"}, entry_back: [], entry_fore: []}

      result =
        Navigation.move_to("back", sent, %{
          assigns()
          | entry_back: [prev],
            entry_fore: []
        })

      # The popped entry is merged with its own back history and the current
      # state is pushed onto the forward stack.
      assert result.view == :profiles
      assert result.entry == {:profile, "z"}
      assert result.entry_back == []
      assert result.entry_fore == [sent]
    end

    test "'forward' pops the next-forward entry" do
      next = %{view: :profiles, entry: {:profile, "z"}, entry_back: [], entry_fore: []}
      sent = %{view: :entries, entry: {:profile, "a"}, entry_back: [], entry_fore: []}

      result =
        Navigation.move_to("forward", sent, %{
          assigns()
          | entry_back: [],
            entry_fore: [next]
        })

      assert result.view == :profiles
      assert result.entry == {:profile, "z"}
      assert result.entry_back == [sent]
      assert result.entry_fore == []
    end

    test "'new' does not record a back entry (no existence check / no prior state)" do
      result = Navigation.move_to("new", :current, assigns())
      # 'new' resolves to the same entry with no history bookkeeping
      assert %{view: :entries, entry: {:profile, "a"}, entry_back: [], entry_fore: []} = result
    end
  end
end
