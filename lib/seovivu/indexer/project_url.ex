defmodule Seovivu.Indexer.ProjectUrl do
  @moduledoc "A single URL within an index-submission project."
  use Ecto.Schema
  import Ecto.Changeset

  @statuses [:pending, :submitted, :done, :failed]

  schema "index_project_urls" do
    field :url, :string
    field :status, Ecto.Enum, values: @statuses, default: :pending

    belongs_to :project, Seovivu.Indexer.Project

    timestamps(type: :utc_datetime)
  end

  def changeset(project_url, attrs) do
    project_url
    |> cast(attrs, [:project_id, :url, :status])
    |> validate_required([:project_id, :url])
  end
end
