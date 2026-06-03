defmodule Seovivu.Repo.Migrations.CreateLoginLogs do
  use Ecto.Migration

  def change do
    create table(:login_logs) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :ip_address, :string
      add :user_agent, :string

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:login_logs, [:user_id])
  end
end
