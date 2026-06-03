# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# It is idempotent: running it repeatedly will not create duplicates.

alias Seovivu.{Accounts, Billing, Settings}
alias Seovivu.Accounts.User

# Ensure a per-feature concurrency row exists for every feature (default 5).
Settings.ensure_feature_concurrency_defaults()

# Seed an admin account. Telegram-based accounts normally come from the bot;
# this one is created directly so you can log in before the bot is configured.
admin_telegram_id = 1
admin_password = System.get_env("ADMIN_PASSWORD", "admin12345")

admin =
  case Accounts.get_user_by_telegram_id(admin_telegram_id) do
    nil ->
      {:ok, user} =
        %User{}
        |> User.telegram_changeset(%{
          telegram_id: admin_telegram_id,
          telegram_username: "admin",
          telegram_first_name: "Admin",
          username: "admin",
          role: :admin
        })
        |> Seovivu.Repo.insert()

      {:ok, user} = Accounts.set_password(user, admin_password)
      Billing.ensure_wallets(user.id)
      IO.puts("Seeded admin user 'admin' with password: #{admin_password}")
      user

    user ->
      IO.puts("Admin user already exists (telegram_id=#{admin_telegram_id}).")
      user
  end

# Give the admin some main credits + a 30-day window so the dashboard has data.
main = Billing.get_wallet(admin.id, :main)

if main && main.credits == 0 do
  Billing.admin_adjust(main, 12_450, %{"seed" => true})

  main
  |> Seovivu.Repo.reload!()
  |> Ecto.Changeset.change(
    expires_at:
      DateTime.add(DateTime.utc_now(), 30 * 86_400, :second) |> DateTime.truncate(:second)
  )
  |> Seovivu.Repo.update!()
end
