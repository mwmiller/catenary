defmodule Catenary.VersionTest do
  @moduledoc """
  Guards the one thing `mix version.set` cannot enforce on its own: that the
  files it writes are still shaped the way it expects.

  The task fails loudly when an anchor stops matching, but only if someone
  remembers to run it. Cargo.toml is also self-syncing, so a drift between
  the committed manifest and the lock would otherwise sit unnoticed until a
  release. These checks run in CI.

  Each extraction is written independently of the task's own anchors on
  purpose. Sharing them would make this test agree with the task even when
  both had been broken by the same reformat, which is the case worth
  catching.
  """
  use ExUnit.Case, async: true

  @root Path.expand("../..", __DIR__)

  # Cargo.toml is the reference: cargo has no include mechanism for a manifest
  # field, so the version has to be a literal there and cannot be derived.
  @reference "src-tauri/Cargo.toml"

  test "the crate manifest carries the version the app reports" do
    assert manifest_version() == Mix.Project.config()[:version]
  end

  test "every file recording the version agrees with the manifest" do
    reference = manifest_version()

    for path <- [
          "mix.exs",
          "src-tauri/tauri.conf.json",
          "src-tauri/Cargo.lock"
        ] do
      assert read(path) == reference,
             "#{path} records #{inspect(read(path))} but #{@reference} has " <>
               "#{reference}; run `mix version.set #{reference}`"
    end
  end

  test "the mix task reads back the same version the manifest records" do
    assert Mix.Tasks.Version.Set.current() == manifest_version()
  end

  defp manifest_version, do: capture(@reference, ~r/^version = "([^"]+)"/m)

  defp read("mix.exs"), do: capture("mix.exs", ~r/version: "([^"]+)"/)

  defp read("src-tauri/tauri.conf.json"),
    do: capture("src-tauri/tauri.conf.json", ~r/^  "version": "([^"]+)"/m)

  # Anchored on the package name so a dependency that happens to be called
  # catenary-something cannot be picked up instead.
  defp read("src-tauri/Cargo.lock"),
    do: capture("src-tauri/Cargo.lock", ~r/^name = "catenary"\nversion = "([^"]+)"/m)

  defp read(path), do: raise("no version reader for #{path}")

  defp capture(path, re) do
    case Regex.run(re, File.read!(Path.join(@root, path))) do
      [_, version] ->
        version

      nil ->
        raise "could not read a version out of #{path}"
    end
  end
end
