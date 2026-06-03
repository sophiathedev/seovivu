defmodule Seovivu.TelegramTest do
  # async: false — Settings is cached in a process-global :persistent_term, so
  # template writes must not race with other tests.
  use Seovivu.DataCase, async: false
  use Oban.Testing, repo: Seovivu.Repo

  alias Seovivu.{Accounts, Telegram}
  alias Seovivu.Accounts.User
  alias Seovivu.Telegram.Workers.{BroadcastWorker, SendMessageWorker}

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

  describe "templates" do
    test "render_template substitutes placeholders in the default template" do
      out = Telegram.render_template("reset", %{password: "s3cret"})
      assert out =~ "s3cret"
      refute out =~ "{{"
    end

    test "put_template overrides the default and is used by render_template" do
      :ok = Telegram.put_template("welcome", "Xin chào {{username}}, mật khẩu {{password}}")
      assert Telegram.get_template("welcome") == "Xin chào {{username}}, mật khẩu {{password}}"

      assert Telegram.render_template("welcome", %{username: "an", password: "pw"}) ==
               "Xin chào an, mật khẩu pw"
    end

    test "put_template rejects unknown keys" do
      assert {:error, :unknown_template} = Telegram.put_template("nope", "x")
    end
  end

  describe "broadcast/1" do
    test "rejects empty text" do
      assert {:error, :empty} = Telegram.broadcast("   ")
    end

    test "enqueues a BroadcastWorker and reports the recipient count" do
      create_user()
      create_user()
      banned = create_user()
      {:ok, _} = Accounts.ban_user(banned)

      assert {:ok, 2} = Telegram.broadcast("Thông báo thử")
      assert_enqueued(worker: BroadcastWorker, args: %{"text" => "Thông báo thử"})
    end

    test "BroadcastWorker fans out one SendMessageWorker per active user" do
      a = create_user()
      b = create_user()

      assert :ok = perform_job(BroadcastWorker, %{"text" => "hi"})

      sends = all_enqueued(worker: SendMessageWorker)
      chat_ids = Enum.map(sends, & &1.args["chat_id"])
      assert a.telegram_id in chat_ids
      assert b.telegram_id in chat_ids
      assert Enum.all?(sends, &(&1.args["text"] == "hi"))
    end
  end

  describe "issuing passwords to imported users" do
    test "sets a password and enqueues a DM for each password-less user, skipping others" do
      u1 = create_user()
      u2 = create_user()
      already = create_user()
      {:ok, _} = Accounts.set_password(already, "already-set-pw")

      assert Telegram.issue_passwords_to_passwordless_users() == 2

      assert Accounts.get_user(u1.id).hashed_password
      assert Accounts.get_user(u2.id).hashed_password
      assert Accounts.count_users_without_password() == 0

      sends = all_enqueued(worker: SendMessageWorker)
      chat_ids = Enum.map(sends, & &1.args["chat_id"])
      assert u1.telegram_id in chat_ids
      assert u2.telegram_id in chat_ids
    end
  end
end
