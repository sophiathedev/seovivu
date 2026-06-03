defmodule Seovivu.Billing.Workers.CheckPackagesWorker do
  @moduledoc """
  Daily package-expiry sweep (scheduled via Oban Cron):

    * Reminds users whose package expires in ~3 days (Telegram).
    * Expires wallets past `expires_at` — zeroes credits, clears the package,
      records an `:expiry` ledger entry — and notifies the user.

  The reminder window is the half-open `(now+2d, now+3d]` band, which a given
  wallet falls into exactly once across daily runs, so reminders don't repeat.
  """
  use Oban.Worker, queue: :default, max_attempts: 1

  alias Seovivu.{Billing, Telegram}

  @impl Oban.Worker
  def perform(_job) do
    now = DateTime.utc_now()
    remind_expiring(now)
    expire_due(now)
    :ok
  end

  defp remind_expiring(now) do
    from = DateTime.add(now, 2 * 86_400, :second)
    to = DateTime.add(now, 3 * 86_400, :second)

    Billing.list_wallets_expiring_between(from, to)
    |> Enum.each(fn wallet ->
      notify(
        wallet,
        "Gói #{kind_label(wallet.kind)} của bạn sẽ hết hạn trong khoảng 3 ngày tới. " <>
          "Hãy gia hạn để không bị gián đoạn dịch vụ."
      )
    end)
  end

  defp expire_due(now) do
    now
    |> Billing.list_expired_wallets()
    |> Enum.each(fn wallet ->
      {:ok, _} = Billing.expire_wallet(wallet)

      notify(
        wallet,
        "Gói #{kind_label(wallet.kind)} của bạn đã hết hạn. Credit còn lại đã được đặt về 0. " <>
          "Vui lòng liên hệ admin để gia hạn."
      )
    end)
  end

  defp notify(%{user: %{telegram_id: telegram_id}}, text) when is_integer(telegram_id) do
    Telegram.send_message_async(telegram_id, text)
  end

  defp notify(_wallet, _text), do: :ok

  defp kind_label(:index), do: "Gửi Index"
  defp kind_label(_), do: "chính"
end
