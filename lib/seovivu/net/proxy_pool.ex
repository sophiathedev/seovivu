defmodule Seovivu.Net.ProxyPool do
  @moduledoc """
  In-memory cache of active proxies with random rotation, so the proxied check
  tools pick a fresh egress per request without a DB round-trip. The cache is
  loaded at boot and refreshed periodically; `refresh/0` forces a reload after
  admin edits.
  """
  use GenServer

  alias Seovivu.Net

  @table __MODULE__
  @refresh_interval :timer.minutes(1)

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Forces an immediate reload of the proxy cache (call after admin edits)."
  def refresh do
    if Process.whereis(__MODULE__), do: GenServer.cast(__MODULE__, :refresh)
    :ok
  end

  @doc """
  Returns `{:ok, proxy}` with a random active proxy, or `:none` when no proxy is
  available (callers must NOT fall back to a direct request — that would leak the
  origin IP).
  """
  def random do
    case :ets.lookup(@table, :proxies) do
      [{:proxies, [_ | _] = proxies}] -> {:ok, Enum.random(proxies)}
      _ -> :none
    end
  end

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    load()
    schedule()
    {:ok, %{}}
  end

  @impl true
  def handle_cast(:refresh, state) do
    load()
    {:noreply, state}
  end

  @impl true
  def handle_info(:refresh, state) do
    load()
    schedule()
    {:noreply, state}
  end

  defp load do
    :ets.insert(@table, {:proxies, Net.list_active_proxies()})
  rescue
    # Keep the last cached pool on a transient DB error instead of crashing.
    error ->
      require Logger
      Logger.warning("ProxyPool reload skipped: #{inspect(error)}")
      :ok
  catch
    # DBConnection ownership loss surfaces as an exit, not a raise.
    :exit, reason ->
      require Logger
      Logger.warning("ProxyPool reload skipped: #{inspect(reason)}")
      :ok
  end

  defp schedule, do: Process.send_after(self(), :refresh, @refresh_interval)
end
