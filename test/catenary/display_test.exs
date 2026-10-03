defmodule Catenary.DisplayTest do
  use ExUnit.Case, async: true

  alias Catenary.Display

  # The Unshown explorer skips app plumbing (see Apps.social_backlog?/1),
  # but whatever still opens one — a ref, the entry viewer's generic path —
  # deserves the record's own name rather than the catch-all placeholder.
  test "app records title by their kind" do
    assert Display.entry_title(:app, %{"type" => "manifest"}) == "⸤App Manifest⸣"
    assert Display.entry_title(:app, %{"type" => "artifact"}) == "⸤App Artifact⸣"
    assert Display.entry_title(:app, %{"type" => "source"}) == "⸤App Source⸣"
  end

  test "a channel message titles by its app" do
    assert Display.entry_title(:app, %{"type" => "note", "app" => "hello-app"}) ==
             "⸤Note from hello-app⸣"

    assert Display.entry_title(:app, %{"type" => "note"}) == "⸤App Note⸣"
  end

  test "a given title wins over the kind" do
    assert Display.entry_title(:app, %{"type" => "manifest", "title" => "Panel App"}) ==
             "Panel App"
  end
end
