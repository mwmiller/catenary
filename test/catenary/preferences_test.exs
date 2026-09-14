defmodule Catenary.PreferencesTest do
  use ExUnit.Case, async: false

  alias Catenary.Preferences

  import ExUnit.CaptureLog

  describe "resolve_identity/1" do
    test "preserves a recorded identity whose keys are missing instead of minting a new one" do
      key = "DeadBeefIdentityKeyNotFoundInStore0000000000000"

      log =
        capture_log(fn ->
          assert Preferences.resolve_identity(key) == key
        end)

      assert log =~ "Refusing to mint a replacement"
    end

    test "returns an extant identity unchanged" do
      name = "preferences-test-#{System.unique_integer([:positive])}"
      key = Baobab.Identity.create(name)

      on_exit(fn -> Baobab.Identity.drop(name) end)

      assert Preferences.resolve_identity(key) == key
      assert Baobab.Identity.key(name, :public)
    end
  end
end