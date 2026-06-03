defmodule Seovivu.Accounts.User do
  @moduledoc """
  A user account, keyed by their Telegram ID.

  Accounts are created when a user starts the Telegram bot; the bot delivers a
  randomly generated password which is stored here as a bcrypt hash. There is
  no email-based flow — Telegram is the only identity channel.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Seovivu.Billing.Wallet
  alias Seovivu.Accounts.LoginLog

  @derive {Inspect, except: [:hashed_password]}
  schema "users" do
    field :telegram_id, :integer
    field :telegram_username, :string
    field :telegram_first_name, :string
    field :telegram_last_name, :string
    field :username, :string
    field :hashed_password, :string, redact: true
    field :role, Ecto.Enum, values: [:user, :admin], default: :user
    field :status, Ecto.Enum, values: [:active, :banned], default: :active
    field :last_login_at, :utc_datetime

    # True when the current password was issued by the system (Telegram welcome
    # or an admin/bot reset) and the user must change it before using the app.
    field :must_change_password, :boolean, default: false

    # Virtual field used when generating/setting a new password.
    field :password, :string, virtual: true, redact: true

    has_many :wallets, Wallet
    has_many :login_logs, LoginLog

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating/updating a user from Telegram profile data.
  """
  def telegram_changeset(user, attrs) do
    user
    |> cast(attrs, [
      :telegram_id,
      :telegram_username,
      :telegram_first_name,
      :telegram_last_name,
      :username,
      :role,
      :status
    ])
    |> validate_required([:telegram_id])
    |> maybe_default_username()
    |> unique_constraint(:telegram_id)
  end

  @doc """
  Changeset for admins to edit a user's profile/status/role.
  """
  def admin_changeset(user, attrs) do
    user
    |> cast(attrs, [
      :username,
      :telegram_username,
      :telegram_first_name,
      :telegram_last_name,
      :role,
      :status
    ])
    |> validate_inclusion(:role, [:user, :admin])
    |> validate_inclusion(:status, [:active, :banned])
  end

  @doc """
  Changeset that sets a new password. The plaintext lives in the virtual
  `:password` field and is hashed into `:hashed_password`.
  """
  def password_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:password])
    |> validate_required([:password])
    |> validate_length(:password, min: 8, max: 72)
    |> maybe_hash_password(opts)
  end

  defp maybe_default_username(changeset) do
    case {get_field(changeset, :username), get_field(changeset, :telegram_username)} do
      {nil, tg} when is_binary(tg) -> put_change(changeset, :username, tg)
      _ -> changeset
    end
  end

  defp maybe_hash_password(changeset, opts) do
    hash? = Keyword.get(opts, :hash_password, true)
    password = get_change(changeset, :password)

    if hash? && password && changeset.valid? do
      changeset
      |> put_change(:hashed_password, Bcrypt.hash_pwd_salt(password))
      |> delete_change(:password)
    else
      changeset
    end
  end

  @doc """
  Verifies the password against the stored hash.

  Runs a dummy check when there is no user/hash to avoid timing attacks.
  """
  def valid_password?(%__MODULE__{hashed_password: hashed}, password)
      when is_binary(hashed) and byte_size(password) > 0 do
    Bcrypt.verify_pass(password, hashed)
  end

  def valid_password?(_, _) do
    Bcrypt.no_user_verify()
    false
  end
end
