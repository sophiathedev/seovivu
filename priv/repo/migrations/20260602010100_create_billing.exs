defmodule Seovivu.Repo.Migrations.CreateBilling do
  use Ecto.Migration

  def change do
    create table(:packages) do
      add :kind, :string, null: false, default: "main"
      add :name, :string, null: false
      add :credits, :integer, null: false, default: 0
      add :days, :integer, null: false, default: 0
      add :price, :decimal
      add :active, :boolean, null: false, default: true

      timestamps(type: :utc_datetime)
    end

    create index(:packages, [:kind])

    create table(:wallets) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :kind, :string, null: false, default: "main"
      add :credits, :integer, null: false, default: 0
      add :expires_at, :utc_datetime
      add :current_package_id, references(:packages, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:wallets, [:user_id, :kind])

    create table(:ledger_entries) do
      add :wallet_id, references(:wallets, on_delete: :delete_all), null: false
      add :delta, :integer, null: false
      add :reason, :string, null: false
      add :feature, :string
      add :meta, :map, null: false, default: %{}

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:ledger_entries, [:wallet_id])
  end
end
