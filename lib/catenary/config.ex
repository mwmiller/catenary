defmodule Catenary.Config do
  @moduledoc """
  Optional TOML clump configuration.

  When `<home>/clumps.toml` exists it *replaces* the clumps configured in
  `config/runtime.exs`; absent, empty, or unparseable files fall back to the
  application env unchanged (see `plan-clump-config.md`).

  Clump ids are arbitrary strings: every top-level TOML table maps to one
  clump keyed by the unchanged table key.
  """

  require Logger

  @default_port 8483

  @doc "Path of the optional clumps.toml file."
  def clumps_path(home \\ Catenary.home_dir()), do: Path.join(home, "clumps.toml")

  @doc """
  Loads and normalizes clumps.toml.

  Returns `nil` when the file is absent, empty, or fails to parse (a loud
  error is logged for the invalid case).
  """
  def load_clumps(home \\ Catenary.home_dir()) do
    case File.read(clumps_path(home)) do
      {:ok, contents} ->
        case decode(contents) do
          {:ok, clumps} when map_size(clumps) == 0 ->
            Logger.info("Ignoring empty #{clumps_path(home)}")
            nil

          {:ok, clumps} ->
            clumps

          {:error, reason} ->
            Logger.error("Ignoring #{clumps_path(home)}: #{reason}")
            nil
        end

      {:error, _} ->
        nil
    end
  end

  @doc """
  Parses TOML clump config text into a normalized clumps map of the same
  shape `config/runtime.exs` uses: `%{id => [port: ..., announce: ...,
  cryouts: ...]}`.
  """
  def decode(contents) do
    case Toml.decode(contents) do
      {:ok, doc} -> normalize(doc)
      {:error, {:invalid_toml, msg}} -> {:error, msg}
      {:error, other} -> {:error, inspect(other)}
    end
  end

  @doc """
  Parses a period shorthand (`"7m"`, `"1h30m15s"`, `"300"`) into total
  seconds. Returns `{:ok, seconds}` or `{:error, reason}`.
  """
  def parse_period(period) do
    case period_runs(String.trim(period), 0) do
      {:ok, seconds} when seconds > 0 -> {:ok, seconds}
      {:ok, _} -> {:error, "period must be positive: #{inspect(period)}"}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Parses a cryout shorthand string (`"mdns"`, `"mdns 5m"`, `"host"`,
  `"host:port"`, `"host:port 15m"`) into a `Baby` cryout keyword list.
  """
  def parse_cryout(s) do
    case String.split(s) do
      ["mdns"] ->
        {:ok, [mdns: true]}

      ["mdns", period] ->
        with {:ok, seconds} <- parse_period(period) do
          {:ok, [mdns: [period: {seconds, :second}]]}
        end

      [host_token] ->
        with {:ok, {host, port}} <- host_port(host_token) do
          {:ok, [host: host, port: port || @default_port]}
        end

      [host_token, period] ->
        with {:ok, {host, port}} <- host_port(host_token),
             {:ok, seconds} <- parse_period(period) do
          {:ok, [host: host, port: port || @default_port, period: {seconds, :second}]}
        end

      _ ->
        {:error, "could not understand #{inspect(s)}"}
    end
  end

  defp normalize(doc) do
    Enum.reduce_while(doc, {:ok, %{}}, fn {id, _table} = entry, {:ok, acc} ->
      case normalize_entry(entry) do
        {:ok, clump} -> {:cont, {:ok, Map.put(acc, to_string(id), clump)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp normalize_entry({id, table}) when is_map(table) do
    case normalize_clump(table) do
      {:ok, clump} -> {:ok, clump}
      {:error, reason} -> {:error, "clump \"#{to_string(id)}\": #{reason}"}
    end
  end

  defp normalize_entry({id, table}) do
    {:error, "expected a table (not #{inspect(table)}) for clump \"#{to_string(id)}\""}
  end

  defp normalize_clump(table) do
    with {:ok, port} <- table_int(table, "port", 0),
         {:ok, announce} <- table_bool(table, "announce", false),
         {:ok, cryouts} <- table_cryouts(table) do
      announce =
        case {announce, table["instance"]} do
          {true, instance} when is_binary(instance) -> [instance: instance]
          _ -> announce
        end

      {:ok, [port: port, announce: announce, cryouts: cryouts]}
    end
  end

  defp table_int(table, key, default) do
    case Map.get(table, key, default) do
      port when is_integer(port) and port in 0..65_535 -> {:ok, port}
      port -> {:error, "#{key} must be an integer in 0..65535, got #{inspect(port)}"}
    end
  end

  defp table_bool(table, key, default) do
    case Map.get(table, key, default) do
      value when is_boolean(value) -> {:ok, value}
      value -> {:error, "#{key} must be a boolean, got #{inspect(value)}"}
    end
  end

  defp table_cryouts(table) do
    case Map.get(table, "cryouts", []) do
      cryouts when is_list(cryouts) -> compile_cryouts(cryouts)
      other -> {:error, "cryouts must be an array of strings, got #{inspect(other)}"}
    end
  end

  defp compile_cryouts(cryouts) do
    Enum.reduce_while(cryouts, {:ok, []}, fn s, {:ok, acc} -> step_cryout(s, acc) end)
    |> finalize_cryouts()
  end

  defp step_cryout(s, acc) when is_binary(s) do
    case parse_cryout(s) do
      {:ok, cryout} -> {:cont, {:ok, [cryout | acc]}}
      {:error, reason} -> {:halt, {:error, "cryout \"#{s}\": #{reason}"}}
    end
  end

  defp step_cryout(other, _acc) do
    {:halt, {:error, "cryout #{inspect(other)} must be a string"}}
  end

  defp finalize_cryouts({:ok, cryouts}) when is_list(cryouts), do: {:ok, Enum.reverse(cryouts)}
  defp finalize_cryouts(error = {:error, _}), do: error

  defp host_port(token) do
    cond do
      String.starts_with?(token, "[") -> bracket_host_port(token)
      colons(token) == 1 -> one_colon_host_port(token)
      true -> {:ok, {token, nil}}
    end
  end

  defp bracket_host_port(token) do
    case Regex.run(~r/^\[([^\]]+)\](?::(\d+))?$/, token) do
      [_, host] -> {:ok, {host, nil}}
      [_, host, port] -> {:ok, {host, String.to_integer(port)}}
      nil -> {:error, "bad bracketed host #{inspect(token)}"}
    end
  end

  defp one_colon_host_port(token) do
    case String.split(token, ":") do
      [host, port] -> parse_port(token, host, port)
      _ -> {:error, "bad host #{inspect(token)}"}
    end
  end

  defp parse_port(token, host, port) do
    case Integer.parse(port) do
      {n, ""} when n > 0 and n <= 65_535 -> {:ok, {host, n}}
      _ -> {:error, "bad port in #{inspect(token)}"}
    end
  end

  defp colons(s), do: s |> String.split(":") |> length() |> Kernel.-(1)

  defp period_runs("", acc), do: {:ok, acc}

  defp period_runs(s, acc) do
    case Integer.parse(String.trim_leading(s)) do
      {n, rest} ->
        case rest do
          <<unit, tail::binary>> when unit in ~c"smh" ->
            period_runs(String.trim_leading(tail), acc + n * unit_seconds(unit))

          "" ->
            # A bare numeric period is seconds.
            period_runs("", acc + n)

          _ ->
            {:error, "bad period near #{inspect(rest)}"}
        end

      :error ->
        {:error, "bad period #{inspect(s)}"}
    end
  end

  defp unit_seconds(?s), do: 1
  defp unit_seconds(?m), do: 60
  defp unit_seconds(?h), do: 3600
end
