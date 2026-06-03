defmodule Seovivu.Accounts do
  @moduledoc """
  User accounts, Telegram-based registration, password management, session
  tokens and login auditing, plus the admin user-management API.
  """
  import Ecto.Query, warn: false

  alias Seovivu.Repo
  alias Seovivu.Accounts.{User, UserToken, LoginLog}
  alias Seovivu.Billing

  ## Lookups

  def get_user!(id), do: Repo.get!(User, id)
  def get_user(id), do: Repo.get(User, id)
  def get_user_by_telegram_id(telegram_id), do: Repo.get_by(User, telegram_id: telegram_id)

  @doc "Loads a user with both wallets (and their current package) preloaded."
  def get_user_with_wallets!(id) do
    User |> Repo.get!(id) |> Repo.preload(wallets: :current_package)
  end

  ## Telegram registration

  @doc """
  Creates or updates a user from Telegram profile data. On first creation it
  provisions both wallets and a random password, returning the plaintext so the
  bot can DM it.

  Returns `{:ok, %{user: user, password: plaintext | nil}}`. `password` is nil
  when the user already existed (use `reset_password/1` to re-issue).
  """
  def register_via_telegram(attrs) do
    telegram_id = attrs[:telegram_id] || attrs["telegram_id"]

    case get_user_by_telegram_id(telegram_id) do
      nil ->
        password = generate_password()

        Repo.transaction(fn ->
          user =
            %User{}
            |> User.telegram_changeset(attrs)
            |> Repo.insert!()

          user =
            user
            |> User.password_changeset(%{password: password})
            |> Ecto.Changeset.put_change(:must_change_password, true)
            |> Repo.update!()

          Billing.ensure_wallets(user.id)
          %{user: user, password: password}
        end)

      %User{} = user ->
        # Keep the profile fresh, but don't touch the password.
        {:ok, user} = user |> User.telegram_changeset(attrs) |> Repo.update()
        Billing.ensure_wallets(user.id)
        {:ok, %{user: user, password: nil}}
    end
  end

  ## Passwords

  @doc "Generates a URL-safe random password."
  def generate_password do
    :crypto.strong_rand_bytes(9) |> Base.url_encode64(padding: false)
  end

  @doc """
  Sets a specific (already-known) plaintext password the user/admin chose, and
  clears the "must change password" flag (the password is no longer a system
  secret the user needs to replace).
  """
  def set_password(%User{} = user, password) do
    user
    |> User.password_changeset(%{password: password})
    |> Ecto.Changeset.put_change(:must_change_password, false)
    |> Repo.update()
  end

  @doc """
  Generates a new random password, stores it, and returns the plaintext. Flags
  the account so the user is forced to change it on next login.
  """
  def reset_password(%User{} = user) do
    password = generate_password()

    result =
      user
      |> User.password_changeset(%{password: password})
      |> Ecto.Changeset.put_change(:must_change_password, true)
      |> Repo.update()

    case result do
      {:ok, user} -> {:ok, user, password}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc "Verifies a plaintext password against the user's stored hash."
  def valid_password?(%User{} = user, password), do: User.valid_password?(user, password)

  @doc """
  Authenticates by Telegram username (or numeric Telegram ID) + password.
  Returns the user on success, otherwise nil. Banned users cannot log in.
  """
  def get_user_by_telegram_and_password(identifier, password)
      when is_binary(identifier) and is_binary(password) do
    user = find_by_identifier(identifier)

    cond do
      is_nil(user) ->
        User.valid_password?(nil, password)
        nil

      user.status == :banned ->
        nil

      User.valid_password?(user, password) ->
        user

      true ->
        nil
    end
  end

  defp find_by_identifier(identifier) do
    case Integer.parse(identifier) do
      {telegram_id, ""} ->
        get_user_by_telegram_id(telegram_id) || Repo.get_by(User, username: identifier)

      _ ->
        Repo.get_by(User, username: identifier) ||
          Repo.get_by(User, telegram_username: identifier)
    end
  end

  ## Session tokens

  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  def delete_user_session_token(token) do
    Repo.delete_all(UserToken.by_token_and_context_query(token, "session"))
    :ok
  end

  ## Login auditing

  @doc "Records a successful login (timestamp + IP) and returns the user."
  def log_login(%User{} = user, ip_address, user_agent) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.transaction(fn ->
      user = user |> Ecto.Changeset.change(last_login_at: now) |> Repo.update!()

      %LoginLog{}
      |> LoginLog.changeset(%{user_id: user.id, ip_address: ip_address, user_agent: user_agent})
      |> Repo.insert!()

      user
    end)
  end

  def list_login_logs(user_id, limit \\ 100) do
    LoginLog
    |> where(user_id: ^user_id)
    |> order_by(desc: :id)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc "Telegram chat ids of all active users (for broadcasts)."
  def list_active_user_telegram_ids do
    User
    |> where([u], u.status == :active and not is_nil(u.telegram_id))
    |> select([u], u.telegram_id)
    |> Repo.all()
  end

  ## Admin user management

  @doc """
  Lists users with wallets preloaded, optionally filtered by a search term
  (matches username, telegram username, or telegram ID). Supports offset paging.
  """
  def list_users(opts \\ []) do
    search = Keyword.get(opts, :search)
    limit = Keyword.get(opts, :limit, 25)
    offset = Keyword.get(opts, :offset, 0)

    User
    |> maybe_search(search)
    |> order_by(desc: :id)
    |> limit(^limit)
    |> offset(^offset)
    |> Repo.all()
    |> Repo.preload(wallets: :current_package)
  end

  def count_users(opts \\ []) do
    User
    |> maybe_search(Keyword.get(opts, :search))
    |> maybe_status(Keyword.get(opts, :status))
    |> Repo.aggregate(:count, :id)
  end

  defp maybe_status(query, status) when status in [:active, :banned] do
    from u in query, where: u.status == ^status
  end

  defp maybe_status(query, _), do: query

  defp maybe_search(query, term) when is_binary(term) and term != "" do
    like = "%#{term}%"

    base =
      from u in query,
        where: ilike(u.username, ^like) or ilike(u.telegram_username, ^like)

    case Integer.parse(term) do
      {id, ""} -> from u in base, or_where: u.telegram_id == ^id
      _ -> base
    end
  end

  defp maybe_search(query, _), do: query

  @doc """
  Active users that have a Telegram chat but no password yet (e.g. accounts
  imported from the old WebIndex data). These can be issued a password and have
  it delivered over Telegram.
  """
  def list_users_without_password do
    User |> without_password_query() |> Repo.all()
  end

  @doc "Count of active, Telegram-reachable users with no password set yet."
  def count_users_without_password do
    User |> without_password_query() |> Repo.aggregate(:count, :id)
  end

  defp without_password_query(query) do
    from u in query,
      where:
        is_nil(u.hashed_password) and u.status == :active and
          not is_nil(u.telegram_id) and u.telegram_id != 0
  end

  def change_user_admin(%User{} = user, attrs \\ %{}), do: User.admin_changeset(user, attrs)

  def update_user_admin(%User{} = user, attrs) do
    user |> User.admin_changeset(attrs) |> Repo.update()
  end

  def ban_user(%User{} = user), do: update_user_admin(user, %{status: :banned})
  def unban_user(%User{} = user), do: update_user_admin(user, %{status: :active})

  def delete_user(%User{} = user), do: Repo.delete(user)
end
