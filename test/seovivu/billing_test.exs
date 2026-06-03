defmodule Seovivu.BillingTest do
  use Seovivu.DataCase, async: true

  alias Seovivu.Billing
  alias Seovivu.Accounts.User

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

  defp set_expiry(wallet, datetime) do
    wallet
    |> Ecto.Changeset.change(expires_at: DateTime.truncate(datetime, :second))
    |> Repo.update!()
  end

  describe "set_days_remaining" do
    test "sets expires_at to now + days without touching credits or package" do
      user = user_fixture()
      wallet = Billing.get_wallet(user.id, :main)
      {:ok, wallet} = Billing.admin_adjust(wallet, 100)

      {:ok, updated} = Billing.set_days_remaining(wallet, 15)

      assert Billing.days_remaining(updated) == 15
      assert updated.credits == 100
      reasons = Billing.list_ledger_entries(wallet.id) |> Enum.map(& &1.reason)
      assert :admin_adjust in reasons
    end

    test "days of 0 expires the window immediately" do
      user = user_fixture()
      wallet = Billing.get_wallet(user.id, :main)

      {:ok, updated} = Billing.set_days_remaining(wallet, 0)

      assert Billing.days_remaining(updated) == 0
    end
  end

  describe "package expiry" do
    test "expire_wallet zeroes credits, clears package, and records an :expiry ledger entry" do
      user = user_fixture()
      wallet = Billing.get_wallet(user.id, :main)
      {:ok, wallet} = Billing.admin_adjust(wallet, 100)

      {:ok, expired} = Billing.expire_wallet(wallet)

      assert expired.credits == 0
      assert expired.current_package_id == nil
      reasons = Billing.list_ledger_entries(wallet.id) |> Enum.map(& &1.reason)
      assert :expiry in reasons
    end

    test "list_expired_wallets finds past-due wallets holding credits, not future ones" do
      past = user_fixture()
      future = user_fixture()

      past_wallet = past.id |> Billing.get_wallet(:main)
      {:ok, past_wallet} = Billing.admin_adjust(past_wallet, 50)
      set_expiry(past_wallet, DateTime.add(DateTime.utc_now(), -3600))

      future_wallet = future.id |> Billing.get_wallet(:main)
      {:ok, future_wallet} = Billing.admin_adjust(future_wallet, 50)
      set_expiry(future_wallet, DateTime.add(DateTime.utc_now(), 30 * 86_400))

      ids = Billing.list_expired_wallets() |> Enum.map(& &1.id)
      assert past_wallet.id in ids
      refute future_wallet.id in ids
    end

    test "list_wallets_expiring_between matches the reminder window" do
      user = user_fixture()
      wallet = Billing.get_wallet(user.id, :main)
      # ~2.5 days out
      set_expiry(wallet, DateTime.add(DateTime.utc_now(), 2 * 86_400 + 43_200))

      now = DateTime.utc_now()
      from = DateTime.add(now, 2 * 86_400)
      to = DateTime.add(now, 3 * 86_400)

      ids = Billing.list_wallets_expiring_between(from, to) |> Enum.map(& &1.id)
      assert wallet.id in ids
    end
  end
end
