defmodule CatenaryWeb.PlaygroundRunTest do
  use ExUnit.Case, async: true

  alias Catenary.Live.AppPlayground
  alias CatenaryWeb.Live

  # A bare socket has no `live_temp`, which is where `push_event/3` writes;
  # the run clause pushes, so the socket under test carries an empty one.
  defp socket(fields) do
    assigns = Map.merge(%{trace: [], trace_at: 0, __changed__: %{}}, Map.new(fields))

    %Phoenix.LiveView.Socket{
      private: %{live_temp: %{}},
      assigns: assigns
    }
  end

  defp pushed(socket), do: socket.private.live_temp[:push_events]

  test "a trace is appended in order and the cursor follows it to the tail" do
    entries = for i <- 1..3, do: %{"kind" => "print", "detail" => "line #{i}"}

    {:noreply, socket} = Live.handle_event("app-trace", %{"entries" => entries}, socket([]))

    assert Enum.map(socket.assigns.trace, & &1["detail"]) == ["line 1", "line 2", "line 3"]
    assert socket.assigns.trace_at == 2
  end

  test "a trace past the cap keeps only the newest entries" do
    entries = for i <- 1..250, do: %{"kind" => "print", "detail" => "line #{i}"}

    {:noreply, socket} = Live.handle_event("app-trace", %{"entries" => entries}, socket([]))

    assert length(socket.assigns.trace) == 200
    assert hd(socket.assigns.trace)["detail"] == "line 51"
    assert List.last(socket.assigns.trace)["detail"] == "line 250"
    assert socket.assigns.trace_at == 199
  end

  test "entries that are not a kind and detail pair are dropped" do
    entries = [
      "nope",
      %{"kind" => "stop"},
      %{"kind" => "print", "detail" => 7},
      %{"kind" => "stop", "detail" => "stopped"}
    ]

    {:noreply, socket} = Live.handle_event("app-trace", %{"entries" => entries}, socket([]))

    assert [%{"kind" => "stop", "detail" => "stopped"}] = socket.assigns.trace
  end

  test "stepping clamps at both ends" do
    entries = for i <- 1..3, do: %{"kind" => "print", "detail" => "#{i}"}
    {:noreply, socket} = Live.handle_event("app-trace", %{"entries" => entries}, socket([]))

    {:noreply, socket} = Live.handle_event("trace-step", %{"value" => "next"}, socket)
    assert socket.assigns.trace_at == 2

    socket =
      Enum.reduce(1..5, socket, fn _, socket ->
        {:noreply, socket} = Live.handle_event("trace-step", %{"value" => "prev"}, socket)
        socket
      end)

    assert socket.assigns.trace_at == 0
  end

  test "the starter buffer compiles to a module" do
    {:noreply, socket} =
      Live.handle_info(:playground_run, socket(source: AppPlayground.starter_source()))

    assert socket.assigns.trace == []
    assert [event, %{"wasm" => wasm}] = List.first(pushed(socket))
    assert event == "app-run"
    module = Base.decode64!(wasm)
    assert binary_part(module, 0, 4) == <<0, 97, 115, 109>>
  end

  test "a buffer that does not parse is a compile entry and a status payload" do
    {:noreply, socket} = Live.handle_info(:playground_run, socket(source: "not wat at all"))

    assert [%{"kind" => "compile", "detail" => detail}] = socket.assigns.trace
    assert is_binary(detail)
    assert [event, %{"error" => message}] = List.first(pushed(socket))
    assert event == "app-run"
    assert is_binary(message)
  end
end
