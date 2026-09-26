defmodule Mix.Tasks.Version.Set do
  @shortdoc "Sets the Catenary version in every file that records one"

  @moduledoc """
  Sets the Catenary version everywhere it is recorded, so it is typed once.

      mix version.set 0.193.0
      mix version.set --next
      mix version.set --check

  `--next` advances to the next prime minor, continuing the sequence the
  project has used since 0.167.0. `--check` reports the version recorded in
  each file and exits nonzero if they disagree, which makes it usable as a
  CI gate.

  The four locations:

    * `mix.exs`                    the Elixir application version
    * `src-tauri/tauri.conf.json`  the version the shipped bundle reports
    * `src-tauri/Cargo.toml`       the crate version
    * `src-tauri/Cargo.lock`       the locked crate version

  Cargo.toml is the one that has to hold a literal: cargo offers no include
  mechanism for a manifest field, so the value cannot be derived from
  anywhere else. Tauri cannot pick it up from Cargo.toml either. Its
  `version` field does accept a path, but only to a `package.json`, and it
  resolves that path against the process working directory rather than
  against the config file's own directory, so the same checkout would
  resolve it differently depending on where the tauri CLI was invoked from.
  That is too fragile to build the release on, so the value is written to
  all four instead.

  Each edit is anchored to surrounding context and must match exactly once.
  A missing or ambiguous anchor is an error rather than a silent no-op, so a
  reformat that breaks a pattern fails loudly instead of leaving one file
  quietly behind.
  """

  use Mix.Task

  @target_files [
    "mix.exs",
    "src-tauri/tauri.conf.json",
    "src-tauri/Cargo.toml",
    "src-tauri/Cargo.lock"
  ]

  @doc """
  Reads the version recorded in `src-tauri/Cargo.toml`, the one location that
  cannot be derived and is therefore treated as the reference value.
  """
  def current do
    path = Path.join(__DIR__, "../../../src-tauri/Cargo.toml")

    case Regex.run(~r/^version = "([^"]+)"/m, File.read!(path)) do
      [_, version] ->
        version

      nil ->
        Mix.raise("could not read a version from #{path}")
    end
  end

  @impl Mix.Task
  def run(argv) do
    {opts, args} = OptionParser.parse!(argv, strict: [next: :boolean, check: :boolean])
    current = current()

    if opts[:check] do
      check(current)
    else
      set(resolve(args, opts, current), current)
    end
  end

  defp resolve([], [next: true], current), do: next_prime(current)
  defp resolve([version], _opts, _current), do: validate!(version)
  defp resolve([], _opts, _current), do: Mix.raise("expected a version, or --next")
  defp resolve(_, _, _), do: Mix.raise("expected exactly one version")

  defp validate!(version) do
    case Version.parse(version) do
      {:ok, parsed} ->
        if blank?(parsed.pre) and blank?(parsed.build) do
          version
        else
          Mix.raise("#{version} must be plain major.minor.patch, with no pre-release or build")
        end

      :error ->
        Mix.raise("#{version} is not a valid version")
    end
  end

  # Version.parse/1 leaves build as nil when there is no build metadata, and as
  # [] when there is an empty one, so both spellings of "nothing here" count.
  defp blank?(nil), do: true
  defp blank?(parts), do: parts == []

  # The minor component tracks the primes: 167, 173, 179, 181, 191, 193. A
  # release that skips a prime is legal, so this only advances to the next one
  # rather than asserting the rule.
  defp next_prime(current) do
    minor =
      current
      |> String.split(".")
      |> Enum.at(1, "0")
      |> String.to_integer()

    # Starts at minor + 1: Stream.iterate/2 emits its seed first, and seeking
    # from the current value would just hand back a version already prime.
    next =
      minor
      |> Kernel.+(1)
      |> Stream.iterate(&(&1 + 1))
      |> Enum.find(&prime?/1)

    "0.#{next}.0"
  end

  defp prime?(n) when n < 2, do: false
  defp prime?(n) when rem(n, 2) == 0, do: n == 2
  defp prime?(n), do: prime_upto?(n, 3)

  defp prime_upto?(n, f) when f * f > n, do: true
  defp prime_upto?(n, f), do: if(rem(n, f) == 0, do: false, else: prime_upto?(n, f + 2))

  defp set(version, current) do
    # Every anchor is resolved before anything is written. Writing as it went
    # along left a half-renamed tree whenever a later file failed to match,
    # which is the one outcome worse than the drift this task exists to
    # prevent: the files then disagree with each other rather than with an
    # out-of-date version.
    pending = Enum.map(@target_files, &prepare/1)
    Enum.each(pending, &commit(&1, version))

    where = "in all #{length(@target_files)} files"

    if version == current do
      Mix.shell().info("already at #{version} #{where}")
    else
      Mix.shell().info("#{current} -> #{version} #{where}")
    end
  end

  # Counted rather than inferred from whether the replacement would change
  # anything: a file already holding the target version and a file whose anchor
  # no longer matches both leave the text untouched, and only the second is a
  # fault.
  defp prepare(file) do
    path = Path.join(__DIR__, "../../../#{file}")
    re = anchor(file)
    original = File.read!(path)

    case length(Regex.scan(re, original)) do
      1 ->
        {path, re, original}

      0 ->
        Mix.raise("#{file} has no version line matching the expected shape")

      n ->
        Mix.raise("#{file} has #{n} lines matching the expected version shape, expected 1")
    end
  end

  defp commit({path, re, original}, version) do
    case Regex.replace(re, original, "\\1\"#{version}\"", global: false) do
      ^original -> :ok
      updated -> File.write!(path, updated)
    end
  end

  # Each capture group 1 keeps the surrounding text, so only the quoted version
  # is rewritten and the surrounding formatting is left alone.
  defp anchor("mix.exs"),
    do: ~r/(app: :catenary,\n\s*version:\s*)"([^"]*)"/m

  defp anchor("src-tauri/tauri.conf.json"),
    do: ~r/^(  "version": )"([^"]*)"/m

  defp anchor("src-tauri/Cargo.toml"),
    do: ~r/^(version = )"([^"]*)"/m

  defp anchor("src-tauri/Cargo.lock"),
    do: ~r/^(name = "catenary"\nversion = )"([^"]*)"/m

  defp anchor(file),
    do: Mix.raise("no version anchor defined for #{file}")

  defp check(reference) do
    results = Enum.map(@target_files, &{&1, recorded(&1)})

    Enum.each(results, fn {file, version} ->
      Mix.shell().info("#{String.pad_trailing(file, 28)} #{version}")
    end)

    case Enum.reject(results, fn {_, version} -> version == reference end) do
      [] ->
        Mix.shell().info("all agree on #{reference}")

      stale ->
        Mix.raise(
          "version mismatch against #{reference}: " <>
            Enum.map_join(stale, ", ", fn {file, version} -> "#{file} reads #{version}" end) <>
            ". Run `mix version.set #{reference}`."
        )
    end
  end

  defp recorded(file) do
    path = Path.join(__DIR__, "../../../#{file}")

    case Regex.run(anchor(file), File.read!(path)) do
      # Group 2 is the version itself, so no guessing at which quoted token in
      # the match is the value: tauri.conf.json and Cargo.lock both carry
      # other quoted text ahead of it.
      [_prefix, _version, version | _] ->
        version

      _ ->
        "not found"
    end
  end
end
