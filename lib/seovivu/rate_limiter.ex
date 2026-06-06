defmodule Seovivu.RateLimiter do
  @moduledoc """
  A tiny in-memory, fixed-window rate limiter backed by a public ETS table.

  `hit/3` records one occurrence of `key` and tells you whether it is still
  within the allowed budget (`limit` hits per `window_ms`). It is used to throttle
  abuse-prone endpoints such as the website's forgot-password action.

  The table is owned by this GenServer (so it survives individual callers) and an
  hourly sweep drops expired windows. Counting happens with atomic ETS ops in the
  caller process, so a high-frequency check never serializes on the GenServer.
  Minor races at a window boundary are acceptable for a throttle of this kind.
  """
  use GenServer

  @table __MODULE__
  @sweep_interval :timer.minutes(10)

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc """
  Records a hit on `key` and returns `:ok` while at/under `limit` within the
  current `window_ms` window, or `{:error, :rate_limited}` once the limit is hit.
  """
  @spec hit(term(), pos_integer(), pos_integer()) :: :ok | {:error, :rate_limited}
  def hit(key, limit, window_ms)
      when is_integer(limit) and limit > 0 and is_integer(window_ms) and window_ms > 0 do
    now = System.monotonic_time(:millisecond)
    expires = now + window_ms

    # Start a fresh window atomically when the key is unseen.
    if :ets.insert_new(@table, {key, 1, expires}) do
      :ok
    else
      case :ets.lookup(@table, key) do
        [{^key, _count, window_end}] when now >= window_end ->
          :ets.insert(@table, {key, 1, expires})
          :ok

        [{^key, count, _window_end}] when count >= limit ->
          {:error, :rate_limited}

        [{^key, _count, _window_end}] ->
          :ets.update_counter(@table, key, {2, 1})
          :ok

        [] ->
          :ets.insert(@table, {key, 1, expires})
          :ok
      end
    end
  end

  @doc "Forgets `key` (e.g. after a successful, legitimate action or in tests)."
  def reset(key), do: :ets.delete(@table, key)

  @doc "Clears all counters (test helper)."
  def clear_all, do: :ets.delete_all_objects(@table)

  ## GenServer

  @impl true
  def init(_opts) do
    :ets.new(@table, [:set, :public, :named_table, read_concurrency: true, write_concurrency: true])
    schedule_sweep()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:sweep, state) do
    now = System.monotonic_time(:millisecond)
    # Delete every entry whose window_end (3rd tuple element) is in the past.
    :ets.select_delete(@table, [{{:_, :_, :"$1"}, [{:<, :"$1", now}], [true]}])
    schedule_sweep()
    {:noreply, state}
  end

  defp schedule_sweep, do: Process.send_after(self(), :sweep, @sweep_interval)
end
