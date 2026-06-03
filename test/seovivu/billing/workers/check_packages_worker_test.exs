defmodule Seovivu.Billing.Workers.CheckPackagesWorkerTest do
  use Seovivu.DataCase, async: true
  use Oban.Testing, repo: Seovivu.Repo

  alias Seovivu.Billing
  alias Seovivu.Accounts.User
  alias Seovivu.Billing.Workers.CheckPackagesWorker
  alias Seovivu.Telegram.Workers.SendMessageWorker

  defp user_fixture do
    {:ok, user} =
      %User{}
      |> User.telegram_changeset(%{
        telegram_id: System.unique_integer([:positive]),
        telegram_username: "u",
        telegram_first_name: "U",
        username: "u#{System.unique_integer([:positive])}",
        role: :user
      })
      |> Repo.insert()

    Billing.ensure_wallets(user.id)
    user
  end

  test "expires past-due wallets and enqueues a Telegram notice" do
    user = user_fixture()
    wallet = Billing.get_wallet(user.id, :main)
    {:ok, wallet} = Billing.admin_adjust(wallet, 80)

    wallet
    |> Ecto.Changeset.change(
      expires_at: DateTime.utc_now() |> DateTime.add(-3600) |> DateTime.truncate(:second)
    )
    |> Repo.update!()

    assert :ok = perform_job(CheckPackagesWorker, %{})

    assert Billing.get_wallet(user.id, :main).credits == 0
    assert_enqueued(worker: SendMessageWorker, args: %{chat_id: user.telegram_id})
  end
end
