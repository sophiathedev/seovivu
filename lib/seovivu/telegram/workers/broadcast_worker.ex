defmodule Seovivu.Telegram.Workers.BroadcastWorker do
  @moduledoc """
  Fans a broadcast message out to every active user by enqueueing one
  `SendMessageWorker` per recipient. Splitting the fan-out from the per-message
  delivery keeps each send independently retryable and rate-limited.
  """
  use Oban.Worker, queue: :telegram, max_attempts: 3

  alias Seovivu.Accounts
  alias Seovivu.Telegram.Workers.SendMessageWorker

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"text" => text}}) do
    Accounts.list_active_user_telegram_ids()
    |> Enum.map(fn chat_id -> SendMessageWorker.new(%{chat_id: chat_id, text: text}) end)
    |> Oban.insert_all()

    :ok
  end
end
