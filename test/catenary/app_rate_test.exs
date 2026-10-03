defmodule Catenary.AppRateTest do
  use ExUnit.Case, async: false

  alias Catenary.{AppHost, AppRate, AppWire, Preferences}

  setup do
    clump_id = Preferences.get(:clump_id)
    pk = Preferences.get(:identity)

    # Every test gets its own bucket: the table and the wall clock are
    # shared, so a fresh slug is what keeps one test's spent window from
    # arriving as the next test's refusal.
    slug = "rate-app-" <> Integer.to_string(System.unique_integer([:positive]))

    %{app: AppHost.app(clump_id, pk, slug), clump_id: clump_id, pk: pk}
  end

  # The suite runs with the budget off (config/test.exs); each test that
  # exercises it puts a ceiling in force for its own assertions and hands
  # the old one back when it is done.
  defp with_burst(burst) do
    previous = Application.fetch_env!(:catenary, :app_rate_burst)
    Application.put_env(:catenary, :app_rate_burst, burst)
    on_exit(fn -> Application.put_env(:catenary, :app_rate_burst, previous) end)
  end

  test "spends the window's tokens, then refuses", ctx do
    with_burst(3)

    assert :ok = AppRate.take(ctx.app)
    assert :ok = AppRate.take(ctx.app)
    assert :ok = AppRate.take(ctx.app)
    assert {:error, :rate_limited} = AppRate.take(ctx.app)
  end

  test "every app carries its own budget", ctx do
    with_burst(1)
    other = AppHost.app(ctx.clump_id, ctx.pk, ctx.app.slug <> "-twin")

    assert :ok = AppRate.take(ctx.app)
    assert {:error, :rate_limited} = AppRate.take(ctx.app)

    # A different listing is a different bucket, even under one identity.
    assert :ok = AppRate.take(other)
  end

  test "the window refills with time", ctx do
    with_burst(1)

    assert :ok = AppRate.take(ctx.app)
    assert {:error, :rate_limited} = AppRate.take(ctx.app)

    Process.sleep(1_100)

    assert :ok = AppRate.take(ctx.app)
  end

  test "the host refuses a call over budget before dispatching it", ctx do
    with_burst(1)

    # The first call runs — its answer is whatever the op makes of it —
    # and the second never reaches the op at all.
    refute AppHost.handle(ctx.app, "log_head", %{log_id: 0}) == {:error, :rate_limited}
    assert {:error, :rate_limited} = AppHost.handle(ctx.app, "log_head", %{log_id: 0})

    # The refusal reaches the worker as plain wire text, like any other.
    reply = AppWire.request(ctx.app, "log_head", AppWire.encode_args(%{"log_id" => 0}))
    assert %{"ok" => false, "error" => "rate_limited"} = reply
  end
end
