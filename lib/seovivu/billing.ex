defmodule Seovivu.Billing do
  @moduledoc """
  Credit wallets and the immutable ledger.

  Two pools per user (`:main`, `:index`). The batch credit model is
  reserve-up-front then refund: `reserve/3` deducts N credits when a batch
  starts, `refund/3` returns credits for URLs that failed or never ran. Every
  movement is recorded in `ledger_entries`.
  """
  import Ecto.Query, warn: false

  alias Seovivu.Repo
  alias Seovivu.Billing.{Wallet, LedgerEntry}
  alias Seovivu.Catalog.Package

  @doc "Gets a user's wallet of the given kind (nil if absent)."
  def get_wallet(user_id, kind), do: Repo.get_by(Wallet, user_id: user_id, kind: kind)

  @doc "Creates the `:main` and `:index` wallets for a user if they don't exist."
  def ensure_wallets(user_id) do
    for kind <- [:main, :index] do
      Repo.insert!(
        %Wallet{user_id: user_id, kind: kind, credits: 0},
        on_conflict: :nothing,
        conflict_target: [:user_id, :kind]
      )
    end

    :ok
  end

  def days_remaining(%Wallet{} = wallet, now \\ DateTime.utc_now()),
    do: Wallet.days_remaining(wallet, now)

  @doc """
  Admin credit adjustment by an arbitrary `delta` (positive to add, negative to
  subtract). Clamps the balance at 0. Records an `:admin_adjust` ledger entry.
  """
  def admin_adjust(%Wallet{} = wallet, delta, meta \\ %{}) when is_integer(delta) do
    Repo.transaction(fn ->
      new_credits = max(0, wallet.credits + delta)
      applied = new_credits - wallet.credits

      wallet = wallet |> Wallet.changeset(%{credits: new_credits}) |> Repo.update!()
      write_entry!(wallet, applied, :admin_adjust, nil, meta)
      wallet
    end)
  end

  @doc """
  Applies a package to a wallet: adds its credits and extends `expires_at` by its
  days (from now, or from the existing expiry if still in the future).
  """
  def apply_package(%Wallet{} = wallet, %Package{} = package, now \\ DateTime.utc_now()) do
    base =
      if wallet.expires_at && DateTime.compare(wallet.expires_at, now) == :gt,
        do: wallet.expires_at,
        else: now

    new_expiry = DateTime.add(base, package.days * 86_400, :second) |> DateTime.truncate(:second)

    Repo.transaction(fn ->
      wallet =
        wallet
        |> Wallet.changeset(%{
          credits: wallet.credits + package.credits,
          expires_at: new_expiry,
          current_package_id: package.id
        })
        |> Repo.update!()

      write_entry!(wallet, package.credits, :upgrade, nil, %{"package" => package.name})
      wallet
    end)
  end

  @doc """
  Sets a wallet's remaining days directly, independent of any package: rewrites
  `expires_at` to `now + days` (in whole days), leaving credits and the current
  package untouched. `days` of 0 expires the window immediately. Records an
  `:admin_adjust` ledger entry (delta 0) for the audit trail.
  """
  def set_days_remaining(%Wallet{} = wallet, days, now \\ DateTime.utc_now())
      when is_integer(days) and days >= 0 do
    new_expiry = DateTime.add(now, days * 86_400, :second) |> DateTime.truncate(:second)

    Repo.transaction(fn ->
      wallet =
        wallet
        |> Wallet.changeset(%{expires_at: new_expiry})
        |> Repo.update!()

      write_entry!(wallet, 0, :admin_adjust, nil, %{"set_days" => days})
      wallet
    end)
  end

  @doc """
  Atomically reserves `amount` credits for a feature run. Returns
  `{:ok, wallet}` or `{:error, :insufficient_credits}`. Safe under concurrency:
  the deduction only applies when the balance is sufficient.
  """
  def reserve(%Wallet{} = wallet, amount, feature) when amount > 0 do
    query =
      from w in Wallet,
        where: w.id == ^wallet.id and w.credits >= ^amount,
        update: [inc: [credits: ^(-amount)]]

    case Repo.update_all(query, []) do
      {1, _} ->
        wallet = Repo.get!(Wallet, wallet.id)
        write_entry!(wallet, -amount, :feature_spend, to_string(feature), %{})
        {:ok, wallet}

      {0, _} ->
        {:error, :insufficient_credits}
    end
  end

  def reserve(%Wallet{} = wallet, 0, _feature), do: {:ok, wallet}

  @doc "Refunds `amount` credits to a wallet (e.g. for failed/unrun URLs)."
  def refund(%Wallet{} = wallet, amount, feature) when amount > 0 do
    {1, _} =
      Repo.update_all(
        from(w in Wallet, where: w.id == ^wallet.id, update: [inc: [credits: ^amount]]),
        []
      )

    wallet = Repo.get!(Wallet, wallet.id)
    write_entry!(wallet, amount, :refund, to_string(feature), %{})
    {:ok, wallet}
  end

  def refund(%Wallet{} = wallet, 0, _feature), do: {:ok, wallet}

  @doc "Total outstanding credits per wallet kind: `%{main: n, index: n}`."
  def totals do
    rows =
      from(w in Wallet, group_by: w.kind, select: {w.kind, coalesce(sum(w.credits), 0)})
      |> Repo.all()
      |> Map.new()

    %{main: Map.get(rows, :main, 0), index: Map.get(rows, :index, 0)}
  end

  ## Package expiry

  @doc """
  Wallets whose package window has ended (`expires_at <= now`) but still hold
  credits or a package — i.e. need expiring. User preloaded.
  """
  def list_expired_wallets(now \\ DateTime.utc_now()) do
    from(w in Wallet,
      where: not is_nil(w.expires_at) and w.expires_at <= ^now,
      where: w.credits > 0 or not is_nil(w.current_package_id)
    )
    |> Repo.all()
    |> Repo.preload(:user)
  end

  @doc """
  Wallets whose package expires within the half-open window `(from, to]` (used to
  send "expiring soon" reminders exactly once). User preloaded.
  """
  def list_wallets_expiring_between(from, to) do
    from(w in Wallet, where: w.expires_at > ^from and w.expires_at <= ^to)
    |> Repo.all()
    |> Repo.preload(:user)
  end

  @doc """
  Expires a wallet: zeroes credits, clears the current package, and records an
  `:expiry` ledger entry for the removed credits. Idempotent-ish (no-op effect
  when already empty, but still clears the package).
  """
  def expire_wallet(%Wallet{} = wallet) do
    Repo.transaction(fn ->
      removed = wallet.credits

      wallet =
        wallet
        |> Wallet.changeset(%{credits: 0, current_package_id: nil})
        |> Repo.update!()

      if removed > 0, do: write_entry!(wallet, -removed, :expiry, nil, %{})
      wallet
    end)
  end

  @doc "Recent ledger entries for a wallet (newest first)."
  def list_ledger_entries(wallet_id, limit \\ 50) do
    LedgerEntry
    |> where(wallet_id: ^wallet_id)
    |> order_by(desc: :id)
    |> limit(^limit)
    |> Repo.all()
  end

  defp write_entry!(wallet, delta, reason, feature, meta) do
    %LedgerEntry{}
    |> LedgerEntry.changeset(%{
      wallet_id: wallet.id,
      delta: delta,
      reason: reason,
      feature: feature,
      meta: meta
    })
    |> Repo.insert!()
  end
end
