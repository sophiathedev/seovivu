defmodule Seovivu.Fixtures do
  @moduledoc "Shared test fixtures for users, admins, and credits."

  alias Seovivu.{Billing, Repo}
  alias Seovivu.Accounts.User

  @doc "Inserts a user (with both wallets provisioned). Pass overrides via `attrs`."
  def user_fixture(attrs \\ %{}) do
    n = System.unique_integer([:positive])

    defaults = %{
      telegram_id: n,
      telegram_username: "u#{n}",
      telegram_first_name: "U#{n}",
      username: "user#{n}",
      role: :user
    }

    {:ok, user} =
      %User{}
      |> User.telegram_changeset(Map.merge(defaults, attrs))
      |> Repo.insert()

    Billing.ensure_wallets(user.id)
    user
  end

  @doc "Inserts an admin user."
  def admin_fixture(attrs \\ %{}), do: user_fixture(Map.merge(%{role: :admin}, attrs))

  @doc "Adds `amount` credits to a user's `kind` wallet and returns the user."
  def with_credits(user, kind, amount) do
    {:ok, _} = Billing.admin_adjust(Billing.get_wallet(user.id, kind), amount)
    user
  end
end
