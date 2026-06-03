defmodule Seovivu.Repo.Migrations.CreateSettingsAndProxies do
  use Ecto.Migration

  def change do
    create table(:settings) do
      add :key, :string, null: false
      add :value, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:settings, [:key])

    create table(:feature_concurrency) do
      add :feature, :string, null: false
      add :per_user_limit, :integer, null: false, default: 5

      timestamps(type: :utc_datetime)
    end

    create unique_index(:feature_concurrency, [:feature])

    create table(:proxies) do
      add :protocol, :string, null: false, default: "http"
      add :host, :string, null: false
      add :port, :integer, null: false
      add :username, :string
      add :password, :string
      add :status, :string, null: false, default: "untested"
      add :last_tested_at, :utc_datetime
      add :last_latency_ms, :integer
      add :active, :boolean, null: false, default: true

      timestamps(type: :utc_datetime)
    end

    create index(:proxies, [:active, :status])
  end
end
