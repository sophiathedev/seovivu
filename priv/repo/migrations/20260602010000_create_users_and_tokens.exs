defmodule Seovivu.Repo.Migrations.CreateUsersAndTokens do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :telegram_id, :bigint, null: false
      add :telegram_username, :string
      add :telegram_first_name, :string
      add :telegram_last_name, :string
      add :username, :string
      add :hashed_password, :string
      add :role, :string, null: false, default: "user"
      add :status, :string, null: false, default: "active"
      add :last_login_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:users, [:telegram_id])
    create index(:users, [:username])

    create table(:users_tokens) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :token, :binary, null: false
      add :context, :string, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:users_tokens, [:user_id])
    create unique_index(:users_tokens, [:context, :token])
  end
end
