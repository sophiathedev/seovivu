defmodule Seovivu.Telegram.Poller do
  @moduledoc """
  Development fallback for receiving Telegram updates without a public HTTPS
  webhook. Long-polls `getUpdates` and dispatches each update through
  `Seovivu.Telegram.handle_update/1`. Idle (cheap) while no token is configured.

  Enabled via `config :seovivu, :telegram_poller, true` (set in dev). In
  production use the webhook instead.
  """
  use GenServer
  require Logger

  alias Seovivu.Telegram
  alias Seovivu.Telegram.Client

  @interval 2_000

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    {:ok, %{offset: 0}, {:continue, :schedule}}
  end

  @impl true
  def handle_continue(:schedule, state), do: {:noreply, schedule(state)}

  @impl true
  def handle_info(:poll, state) do
    # Stand down when no token is set, or when a webhook is active (the two
    # delivery methods are mutually exclusive — getUpdates 409s under a webhook).
    state =
      if Client.configured?() and not Telegram.webhook_active?(), do: poll(state), else: state

    {:noreply, schedule(state)}
  end

  defp schedule(state) do
    Process.send_after(self(), :poll, @interval)
    state
  end

  defp poll(state) do
    case Client.get_updates(state.offset, 0) do
      {:ok, updates} when is_list(updates) and updates != [] ->
        Enum.each(updates, &safe_handle/1)
        %{state | offset: last_update_id(updates) + 1}

      {:ok, _} ->
        state

      # A webhook is active — record it so we stop polling until it's removed.
      {:error, {:telegram, 409, _}} ->
        Telegram.set_webhook_active(true)
        state

      {:error, reason} ->
        Logger.debug("Telegram poller skipped: #{inspect(reason)}")
        state
    end
  end

  defp last_update_id(updates) do
    updates |> List.last() |> Map.get("update_id", state_fallback())
  end

  defp state_fallback, do: 0

  defp safe_handle(update) do
    Telegram.handle_update(update)
  rescue
    error -> Logger.error("Telegram update failed: #{inspect(error)}")
  end
end
