defmodule Mix.Tasks.CreateSuperuser do
  @shortdoc "Creates (or promotes) an admin superuser with a username + password"

  @moduledoc """
  Creates an admin (superuser) account that logs in on the website with a
  username + password — no Telegram required.

  Because every account needs a `telegram_id` (the app is Telegram-first), a
  CLI-created superuser is assigned a unique *negative* sentinel id, which can
  never collide with a real Telegram user id (those are positive).

  ## Usage

      # Interactive — prompts for username and a hidden password (asked twice):
      mix create_superuser

      # Non-interactive (scripts / Docker) — pass them as arguments:
      mix create_superuser <username> <password>

  If the username already exists, that account is updated instead: its password
  is reset and it is promoted to an active admin.
  """
  use Mix.Task

  import Ecto.Query

  alias Seovivu.{Billing, Repo}
  alias Seovivu.Accounts.User

  @requirements ["app.start"]

  @impl Mix.Task
  def run(args) do
    {username, password} = collect(args)

    username = String.trim(username)

    if username == "", do: Mix.raise("Username không được để trống.")

    case Repo.one(from u in User, where: u.username == ^username, limit: 1) do
      nil -> create(username, password)
      %User{} = user -> promote(user, password)
    end
  end

  ## Create / promote

  defp create(username, password) do
    changeset =
      %User{}
      |> User.telegram_changeset(%{
        telegram_id: next_sentinel_id(),
        username: username,
        role: :admin
      })
      |> User.password_changeset(%{password: password})

    case Repo.insert(changeset) do
      {:ok, user} ->
        Billing.ensure_wallets(user.id)
        report("Đã tạo", user)

      {:error, changeset} ->
        Mix.raise(errors(changeset))
    end
  end

  defp promote(user, password) do
    Mix.shell().info("Username '#{user.username}' đã tồn tại — cập nhật mật khẩu và quyền admin.")

    changeset =
      user
      |> User.telegram_changeset(%{role: :admin, status: :active})
      |> User.password_changeset(%{password: password})

    case Repo.update(changeset) do
      {:ok, user} ->
        Billing.ensure_wallets(user.id)
        report("Đã cập nhật", user)

      {:error, changeset} ->
        Mix.raise(errors(changeset))
    end
  end

  # A unique non-positive id, one below the current minimum (so -1, -2, ...).
  # Real Telegram user ids are positive, so these never clash.
  defp next_sentinel_id do
    min(Repo.aggregate(User, :min, :telegram_id) || 0, 0) - 1
  end

  defp report(verb, user) do
    Mix.shell().info([
      :green,
      "✔ #{verb} superuser: ",
      :reset,
      "#{user.username} (id=#{user.id}, telegram_id=#{user.telegram_id}, role=#{user.role})"
    ])
  end

  defp errors(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {k, v}, acc -> String.replace(acc, "%{#{k}}", to_string(v)) end)
    end)
    |> Enum.map_join("; ", fn {field, msgs} -> "#{field} #{Enum.join(msgs, ", ")}" end)
  end

  ## Input collection

  defp collect([username, password | _]), do: {username, password}
  defp collect([username]), do: {username, prompt_password()}
  defp collect([]), do: {prompt_username(), prompt_password()}

  defp prompt_username do
    case IO.gets("Username: ") do
      :eof -> Mix.raise("Không đọc được username.")
      input -> String.trim(to_string(input))
    end
  end

  defp prompt_password do
    p1 = secret_gets("Password: ")
    p2 = secret_gets("Nhập lại password: ")

    cond do
      p1 != p2 ->
        Mix.shell().error("Mật khẩu không khớp, thử lại.\n")
        prompt_password()

      String.length(p1) < 8 ->
        Mix.shell().error("Mật khẩu tối thiểu 8 ký tự, thử lại.\n")
        prompt_password()

      true ->
        p1
    end
  end

  # Reads a line without echoing it: a helper process repeatedly clears the line
  # so typed characters never stay visible. Best-effort (interactive TTY only).
  defp secret_gets(prompt) do
    hider = spawn(fn -> hide_loop(prompt) end)

    value =
      case IO.gets(prompt) do
        :eof -> ""
        input -> String.trim(to_string(input))
      end

    send(hider, :stop)
    IO.write("\n")
    value
  end

  defp hide_loop(prompt) do
    receive do
      :stop -> :ok
    after
      1 ->
        IO.write("\e[2K\r#{prompt}")
        hide_loop(prompt)
    end
  end
end
