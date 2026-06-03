defmodule Seovivu.Repo.Migrations.CreateIndexProjects do
  use Ecto.Migration

  def change do
    create table(:index_projects) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :name, :string, null: false
      # submitted | processing | done
      add :status, :string, null: false, default: "submitted"
      add :manually_processed, :boolean, null: false, default: false
      add :url_count, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:index_projects, [:user_id])
    create index(:index_projects, [:status])

    create table(:index_project_urls) do
      add :project_id, references(:index_projects, on_delete: :delete_all), null: false
      add :url, :text, null: false
      # pending | submitted | done | failed
      add :status, :string, null: false, default: "pending"

      timestamps(type: :utc_datetime)
    end

    create index(:index_project_urls, [:project_id])
  end
end
