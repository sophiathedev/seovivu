# Migrates the old WebIndex (Python/JSON) data into Seovivu.
#
#   mix run priv/repo/seeds/webindex_migration.exs
#
# Source files live in priv/repo/migration_data/ (copied from the old app):
#   * users_db.json     — 326 accounts (Telegram-first)
#   * settings_db.json  — per-tier monthly credit allotments
#
# What it does (phương án A in MIGRATION.md):
#   1. Creates the main-toolkit packages (Free/Basic/VIP/Silver/Gold/Diamond),
#      credits taken from settings_db.json `credit_per_month_*`.
#   2. Imports every user keyed by telegram_id, preserving created_at, role and
#      (for genuine plaintext passwords, i.e. the admins) the original password.
#      Telegram-issued JWT "passwords" are NOT reused — those accounts are left
#      WITHOUT a password (hashed_password = nil). The admin user-manager page
#      surfaces these and can issue + DM passwords in bulk.
#   3. Provisions wallets, restores the user's current credit balance + expiry,
#      and links the wallet to its tier package. Every grant is logged in the
#      ledger.
#
# Idempotent: existing users (by telegram_id) and packages (by name) are skipped.

defmodule WebindexMigration do
  alias Seovivu.{Accounts, Billing, Catalog, Repo}
  alias Seovivu.Accounts.User
  alias Seovivu.Billing.Wallet

  @data_dir Path.expand("../migration_data", __DIR__)

  # Old level (as stored) -> canonical package name. "Sliver" is the old typo.
  @level_to_package %{
    "Free" => "Free",
    "Basic" => "Basic",
    "VIP" => "VIP",
    "Sliver" => "Silver",
    "Silver" => "Silver",
    "Gold" => "Gold",
    "Diamond" => "Diamond"
  }

  def run do
    settings = read_json("settings_db.json")
    users = read_json("users_db.json")

    pkg_map = ensure_packages(settings)
    IO.puts("Packages ready: #{pkg_map |> Map.keys() |> Enum.join(", ")}")

    {created, skipped} =
      Enum.reduce(users, {0, 0}, fn u, {c, s} ->
        case migrate_user(u, pkg_map) do
          :created -> {c + 1, s}
          :skipped -> {c, s + 1}
        end
      end)

    IO.puts("\nMigration done. Users created: #{created}, skipped (already existed): #{skipped}.")
  end

  # --- Packages ----------------------------------------------------------------

  defp ensure_packages(settings) do
    defs = [
      {"Free", 0},
      {"Basic", settings["credit_per_month_basic"] || 0},
      {"VIP", settings["credit_per_month_vip"] || 0},
      {"Silver", settings["credit_per_month_sliver"] || 0},
      {"Gold", settings["credit_per_month_gold"] || 0},
      {"Diamond", settings["credit_per_month_diamond"] || 0}
    ]

    existing = Catalog.list_packages(:main) |> Map.new(&{&1.name, &1})

    Enum.reduce(defs, %{}, fn {name, credits}, acc ->
      pkg =
        case existing[name] do
          nil ->
            {:ok, pkg} =
              Catalog.create_package(%{
                kind: :main,
                name: name,
                credits: credits,
                days: 30,
                price: 0,
                active: true
              })

            pkg

          pkg ->
            pkg
        end

      Map.put(acc, name, pkg)
    end)
  end

  # --- Users -------------------------------------------------------------------

  defp migrate_user(u, pkg_map) do
    telegram_id = u["telegram_id"] || 0

    case Accounts.get_user_by_telegram_id(telegram_id) do
      %User{} ->
        :skipped

      nil ->
        level = u["level"] || "Basic"
        role = if level == "admin", do: :admin, else: :user
        created = parse_dt(u["created_at"]) || now()

        attrs = %{
          telegram_id: telegram_id,
          telegram_username: u["telegram_username"],
          telegram_first_name: u["telegram_first_name"],
          telegram_last_name: u["telegram_last_name"],
          username: u["username"],
          role: role,
          status: :active
        }

        changeset =
          %User{}
          |> User.telegram_changeset(attrs)
          |> Ecto.Changeset.put_change(:inserted_at, created)
          |> Ecto.Changeset.put_change(:updated_at, created)
          |> maybe_put_password(password_for(u))

        {:ok, user} = Repo.insert(changeset)

        provision_wallet(user, u, level, pkg_map)
        :created
    end
  end

  # Restores the user's main wallet: current credit balance, expiry window, and
  # the tier package link. The :index wallet stays at 0 (the old app had no
  # index credit tiers).
  defp provision_wallet(user, u, level, pkg_map) do
    Billing.ensure_wallets(user.id)
    main = Billing.get_wallet(user.id, :main)

    credit = u["credit"]

    if is_integer(credit) and credit > 0 do
      Billing.admin_adjust(main, credit, %{"migrated_from" => "webindex", "level" => level})
    end

    pkg = pkg_map[@level_to_package[level]]
    expires_at = parse_dt(u["expiry_date"])

    if pkg || expires_at do
      main
      |> Repo.reload!()
      |> Wallet.changeset(%{
        expires_at: expires_at,
        current_package_id: pkg && pkg.id
      })
      |> Repo.update!()
    end
  end

  # Genuine plaintext passwords (the admins) are preserved so they can still log
  # in on the web. Telegram JWT tokens (and anything not a usable password) yield
  # `nil` — the account is left password-less for the admin to issue + DM later.
  defp password_for(u) do
    raw = u["password"] || ""

    if raw != "" and not String.starts_with?(raw, "eyJ") and String.length(raw) in 8..72,
      do: raw,
      else: nil
  end

  defp maybe_put_password(changeset, nil), do: changeset
  defp maybe_put_password(changeset, pw), do: User.password_changeset(changeset, %{password: pw})

  # --- Helpers -----------------------------------------------------------------

  defp read_json(file) do
    @data_dir |> Path.join(file) |> File.read!() |> Jason.decode!()
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)

  # Old timestamps are naive strings like "2025-05-22 14:26:42"; treated as UTC.
  defp parse_dt(nil), do: nil
  defp parse_dt(""), do: nil

  defp parse_dt(s) when is_binary(s) do
    case NaiveDateTime.from_iso8601(String.replace(s, " ", "T")) do
      {:ok, ndt} -> DateTime.from_naive!(ndt, "Etc/UTC") |> DateTime.truncate(:second)
      _ -> nil
    end
  end
end

WebindexMigration.run()
