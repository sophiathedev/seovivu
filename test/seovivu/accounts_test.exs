defmodule Seovivu.AccountsTest do
  use Seovivu.DataCase, async: true

  alias Seovivu.Accounts
  alias Seovivu.Accounts.User

  defp create_user(attrs \\ %{}) do
    {:ok, user} =
      %User{}
      |> User.telegram_changeset(
        Map.merge(
          %{
            telegram_id: System.unique_integer([:positive]),
            telegram_username: "u",
            telegram_first_name: "U",
            username: "u#{System.unique_integer([:positive])}",
            role: :user
          },
          attrs
        )
      )
      |> Repo.insert()

    user
  end

  describe "login auditing" do
    test "log_login records ip/user-agent and stamps last_login_at" do
      user = create_user()

      {:ok, _} = Accounts.log_login(user, "1.2.3.4", "Mozilla/5.0")
      {:ok, _} = Accounts.log_login(user, "5.6.7.8", "curl/8")

      logs = Accounts.list_login_logs(user.id)
      assert length(logs) == 2
      # newest first
      assert hd(logs).ip_address == "5.6.7.8"
      assert hd(logs).user_agent == "curl/8"
      assert Accounts.get_user!(user.id).last_login_at
    end
  end

  describe "users without a password" do
    test "counts/lists active, Telegram-reachable users that have no password" do
      no_pw = create_user()
      with_pw = create_user()
      {:ok, _} = Accounts.set_password(with_pw, "has-a-password")
      banned = create_user()
      {:ok, _} = Accounts.ban_user(banned)
      no_chat = create_user(%{telegram_id: 0})

      ids = Accounts.list_users_without_password() |> Enum.map(& &1.id)

      assert no_pw.id in ids
      refute with_pw.id in ids
      refute banned.id in ids
      refute no_chat.id in ids

      assert Accounts.count_users_without_password() == length(ids)
    end
  end

  describe "list_active_user_telegram_ids/0" do
    test "returns active users' telegram ids and excludes banned ones" do
      active = create_user()
      banned = create_user()
      {:ok, _} = Accounts.ban_user(banned)

      ids = Accounts.list_active_user_telegram_ids()
      assert active.telegram_id in ids
      refute banned.telegram_id in ids
    end
  end
end
