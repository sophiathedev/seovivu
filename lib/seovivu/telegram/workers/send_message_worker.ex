defmodule Seovivu.Telegram.Workers.SendMessageWorker do
  @moduledoc "Delivers a single Telegram message, respecting the Bot API rate limit."
  use Oban.Worker, queue: :telegram, max_attempts: 5

  alias Seovivu.Telegram.Client

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"chat_id" => chat_id, "text" => text}}) do
    case Client.send_message(chat_id, text) do
      {:ok, _result} ->
        :ok

      # Rate limited: back off and retry.
      {:error, {:telegram, 429, _}} ->
        {:snooze, 5}

      # No token configured yet: nothing we can do, don't keep retrying.
      {:error, :not_configured} ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end
end
