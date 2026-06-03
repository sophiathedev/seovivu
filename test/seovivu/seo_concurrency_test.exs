defmodule Seovivu.SeoConcurrencyTest do
  @moduledoc """
  Proves the feature engine runs batches CONCURRENTLY across users — user A's
  batch must not block user B's. We inject a fake per-URL runner that sleeps and
  reports its start/end window to the test process, run two users' batches at the
  same time, and assert their execution windows overlap (and that work from both
  users is in flight simultaneously).
  """
  use Seovivu.DataCase, async: false

  import Seovivu.Fixtures
  alias Seovivu.{Seo, Settings}
  alias Seovivu.Settings.FeatureConcurrency

  @sleep_ms 120

  setup do
    test_pid = self()

    # Fake runner: report a start/end window per item, sleep to simulate I/O.
    runner = fn _feature, item, _params ->
      send(test_pid, {:run, :start, item.job_id, System.monotonic_time(:millisecond)})
      Process.sleep(@sleep_ms)
      send(test_pid, {:run, :stop, item.job_id, System.monotonic_time(:millisecond)})
      {:success, %{result: %{}}}
    end

    Application.put_env(:seovivu, :seo_feature_runner, runner)
    on_exit(fn -> Application.delete_env(:seovivu, :seo_feature_runner) end)
    :ok
  end

  test "two users' batches run interleaved, not one-after-the-other" do
    user_a = user_fixture() |> with_credits(:main, 50)
    user_b = user_fixture() |> with_credits(:main, 50)

    {:ok, job_a} = Seo.start_batch(user_a, :check_index, "a1.com\na2.com\na3.com")
    {:ok, job_b} = Seo.start_batch(user_b, :check_index, "b1.com\nb2.com\nb3.com")

    # Run both batches at the same time (seo_async is off in tests, so nothing
    # has started yet — we drive run_job/1 ourselves, concurrently).
    [ra, rb] =
      [job_a, job_b]
      |> Enum.map(fn job -> Task.async(fn -> Seo.run_job(job) end) end)
      |> Task.await_many(10_000)

    assert ra.status == :done
    assert rb.status == :done

    events = drain_events()

    win_a = window(events, job_a.id)
    win_b = window(events, job_b.id)

    # The two batches' execution windows must overlap: B starts before A ends.
    assert overlap?(win_a, win_b),
           "batches ran sequentially — A: #{inspect(win_a)}, B: #{inspect(win_b)}"

    # And at some instant, URLs from BOTH users were in flight at once.
    assert peak_cross_user_inflight(events, job_a.id, job_b.id) >= 2
  end

  test "a single batch fans its URLs out concurrently (bounded by the per-user limit)" do
    # 5 URLs with the default per-user limit of 5 → all run at once. If it were
    # sequential the wall time would be ~5×sleep; concurrently it's ~1×sleep.
    user = user_fixture() |> with_credits(:main, 50)
    {:ok, job} = Seo.start_batch(user, :check_index, "u1\nu2\nu3\nu4\nu5")

    {elapsed_us, result} = :timer.tc(fn -> Seo.run_job(job) end)
    elapsed_ms = div(elapsed_us, 1000)

    assert result.status == :done
    assert result.success_count == 5

    # Generous ceiling: concurrent ≈ 1×sleep; sequential would be ≈ 5×sleep.
    assert elapsed_ms < @sleep_ms * 3,
           "5 URLs took #{elapsed_ms}ms — expected ~#{@sleep_ms}ms if concurrent"
  end

  test "max_concurrency comes from the admin-defined per-feature number" do
    # Admin lowers URL-status concurrency to 3 (default is 5).
    Settings.ensure_feature_concurrency_defaults()
    fc = Repo.get_by!(FeatureConcurrency, feature: :url_status)
    {:ok, _} = Settings.update_feature_concurrency(fc, %{per_user_limit: 3})
    assert Settings.per_user_limit(:url_status) == 3

    user = user_fixture() |> with_credits(:main, 50)
    urls = 1..9 |> Enum.map(&"u#{&1}.com") |> Enum.join("\n")
    {:ok, job} = Seo.start_batch(user, :url_status, urls)

    assert Seo.run_job(job).status == :done

    # Never more than the admin number ran at once — and it really did reach it
    # (proving the admin value flows through, not the default 5).
    assert peak_inflight(drain_events(), job.id) == 3
  end

  ## helpers

  defp drain_events(acc \\ []) do
    receive do
      {:run, _, _, _} = e -> drain_events([e | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  defp window(events, job_id) do
    times = for {:run, _, ^job_id, t} <- events, do: t
    {Enum.min(times), Enum.max(times)}
  end

  # Peak number of one job's URLs in flight at the same instant.
  defp peak_inflight(events, job_id) do
    events
    |> Enum.filter(fn {:run, _, j, _} -> j == job_id end)
    |> Enum.sort_by(fn {:run, _, _, t} -> t end)
    |> Enum.reduce({0, 0}, fn {:run, kind, _, _}, {cur, peak} ->
      cur = cur + if(kind == :start, do: 1, else: -1)
      {cur, max(peak, cur)}
    end)
    |> elem(1)
  end

  defp overlap?({start_a, end_a}, {start_b, end_b}),
    do: max(start_a, start_b) < min(end_a, end_b)

  # Walk the start/stop events in time order; track how many of each job's URLs
  # are in flight and return the peak moment where BOTH jobs had ≥1 in flight.
  defp peak_cross_user_inflight(events, job_a, job_b) do
    events
    |> Enum.sort_by(fn {:run, _, _, t} -> t end)
    |> Enum.reduce({%{job_a => 0, job_b => 0}, 0}, fn {:run, kind, job, _t}, {inflight, peak} ->
      delta = if kind == :start, do: 1, else: -1
      inflight = Map.update(inflight, job, delta, &(&1 + delta))

      cross =
        if inflight[job_a] > 0 and inflight[job_b] > 0,
          do: inflight[job_a] + inflight[job_b],
          else: 0

      {inflight, max(peak, cross)}
    end)
    |> elem(1)
  end
end
