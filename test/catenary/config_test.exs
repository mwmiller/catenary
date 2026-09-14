defmodule Catenary.ConfigTest do
  use ExUnit.Case, async: true

  alias Catenary.Config

  import ExUnit.CaptureLog

  describe "parse_period/1" do
    test "single units" do
      assert Config.parse_period("300") == {:ok, 300}
      assert Config.parse_period("15s") == {:ok, 15}
      assert Config.parse_period("7m") == {:ok, 420}
      assert Config.parse_period("2h") == {:ok, 7200}
    end

    test "compound periods sum to total seconds" do
      assert Config.parse_period("1h30m15s") == {:ok, 5415}
      assert Config.parse_period("1h15m") == {:ok, 4500}
    end

    test "rejects empty, zero, and unknown periods" do
      assert {:error, _} = Config.parse_period("")
      assert {:error, _} = Config.parse_period("0m")
      assert {:error, _} = Config.parse_period("15x")
      assert {:error, _} = Config.parse_period("15m30z")
    end
  end

  describe "parse_cryout/1" do
    test "mdns meta cryouts" do
      assert Config.parse_cryout("mdns") == {:ok, [mdns: true]}
      assert Config.parse_cryout("mdns 5m") == {:ok, [mdns: [period: {300, :second}]]}
    end

    test "fixed hosts default to port 8483" do
      assert Config.parse_cryout("oasis.example.org") ==
               {:ok, [host: "oasis.example.org", port: 8483]}

      assert Config.parse_cryout("192.168.1.23") ==
               {:ok, [host: "192.168.1.23", port: 8483]}
    end

    test "host:port and period" do
      assert Config.parse_cryout("192.168.1.23:8483") ==
               {:ok, [host: "192.168.1.23", port: 8483]}

      assert Config.parse_cryout("clump.example.net:8483 15m") ==
               {:ok, [host: "clump.example.net", port: 8483, period: {900, :second}]}
    end

    test "bracketed and bare IPv6" do
      assert Config.parse_cryout("[2001:db8::1]:8483") ==
               {:ok, [host: "2001:db8::1", port: 8483]}

      assert Config.parse_cryout("2001:db8::1") ==
               {:ok, [host: "2001:db8::1", port: 8483]}
    end

    test "rejects too many tokens and bad ports" do
      assert {:error, _} = Config.parse_cryout("a b c")
      assert {:error, _} = Config.parse_cryout("host:port")
      assert {:error, _} = Config.parse_cryout("host:-1")
    end
  end

  describe "decode/1" do
    test "normalizes a full config to the runtime.exs shape" do
      assert {:ok, clumps} =
               Config.decode("""
               [Quagga]
               port = 8483
               announce = true
               instance = "Main"
               cryouts = ["mdns", "oasis.example.org", "192.168.1.23:8483 15m"]

               [Dev]
               port = 0
               """)

      assert clumps == %{
               "Quagga" => [
                 port: 8483,
                 announce: [instance: "Main"],
                 cryouts: [
                   [mdns: true],
                   [host: "oasis.example.org", port: 8483],
                   [host: "192.168.1.23", port: 8483, period: {900, :second}]
                 ]
               ],
               "Dev" => [port: 0, announce: false, cryouts: []]
             }
    end

    test "clump ids are arbitrary opaque strings" do
      assert {:ok, clumps} =
               Config.decode("""
               ["A dotted.and spaced clump"]
               port = 8483

               ["123? weird"]
               port = 0
               """)

      assert Map.keys(clumps) |> MapSet.new() ==
               MapSet.new(["A dotted.and spaced clump", "123? weird"])
    end

    test "defaults: ephemeral port, no announce, no cryouts" do
      assert {:ok, %{"Standalone" => clump}} = Config.decode("[Standalone]\n")
      assert clump == [port: 0, announce: false, cryouts: []]
    end

    test "rejects invalid TOML" do
      assert {:error, _} = Config.decode("[Quagga]\nport = abc")
    end

    test "rejects non-table clumps and bad field types" do
      assert {:error, _} = Config.decode("clump = 1")
      assert {:error, _} = Config.decode("[Quagga]\nport = \"8483\"")
      assert {:error, _} = Config.decode("[Quagga]\nannounce = \"yes\"")
      assert {:error, _} = Config.decode("[Quagga]\ncryouts = \"mdns\"")
      assert {:error, _} = Config.decode("[Quagga]\ncryouts = [true]")
    end
  end

  describe "load_clumps/1" do
    defp with_home(fun) do
      home = Path.join(System.tmp_dir!(), "catenary-config-#{System.unique_integer([:positive])}")
      File.mkdir_p!(home)
      on_exit(fn -> File.rm_rf!(home) end)
      fun.(home)
    end

    test "returns nil when the file is absent or empty" do
      with_home(fn home ->
        assert Config.load_clumps(home) == nil
        File.write!(Path.join(home, "clumps.toml"), "")
        assert Config.load_clumps(home) == nil
      end)
    end

    test "returns the parsed clumps when present" do
      with_home(fn home ->
        File.write!(Path.join(home, "clumps.toml"), "[Quagga]\nport = 8483\n")

        assert Config.load_clumps(home) == %{
                 "Quagga" => [port: 8483, announce: false, cryouts: []]
               }
      end)
    end

    test "returns nil and logs on invalid config" do
      with_home(fn home ->
        File.write!(Path.join(home, "clumps.toml"), "[Quagga]\nport = abc\n")

        log =
          capture_log(fn ->
            assert Config.load_clumps(home) == nil
          end)

        assert log =~ "Ignoring"
      end)
    end
  end
end
