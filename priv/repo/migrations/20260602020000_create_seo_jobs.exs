defmodule Seovivu.Repo.Migrations.CreateSeoJobs do
  use Ecto.Migration

  def change do
    create table(:seo_jobs) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :feature, :string, null: false
      # running | done | canceled
      add :status, :string, null: false, default: "running"
      add :total, :integer, null: false, default: 0
      add :done, :integer, null: false, default: 0
      add :success_count, :integer, null: false, default: 0
      add :failed_count, :integer, null: false, default: 0
      add :credits_charged, :integer, null: false, default: 0
      add :credits_refunded, :integer, null: false, default: 0
      add :params, :map, null: false, default: %{}
      add :completed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:seo_jobs, [:user_id])
    create index(:seo_jobs, [:user_id, :feature])

    create table(:seo_job_items) do
      add :job_id, references(:seo_jobs, on_delete: :delete_all), null: false
      add :url, :text, null: false
      # pending | running | success | failed
      add :status, :string, null: false, default: "pending"
      add :result, :map, null: false, default: %{}
      add :proxy_id, references(:proxies, on_delete: :nilify_all)
      add :latency_ms, :integer

      timestamps(type: :utc_datetime)
    end

    create index(:seo_job_items, [:job_id])
  end
end
