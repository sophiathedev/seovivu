defmodule Seovivu.Indexer.Project do
  @moduledoc """
  A "Submit Index" project on the index.seovivu.com subdomain: a named batch of
  URLs a user wants pushed to Google for indexing. Drawn against the SEPARATE
  `:index` credit wallet. `manually_processed` is an admin flag (drives a color
  in the review UI) for projects handled by hand.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @statuses [:submitted, :processing, :done]

  schema "index_projects" do
    field :name, :string
    field :status, Ecto.Enum, values: @statuses, default: :submitted
    field :manually_processed, :boolean, default: false
    field :url_count, :integer, default: 0

    belongs_to :user, Seovivu.Accounts.User
    has_many :urls, Seovivu.Indexer.ProjectUrl

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses

  def changeset(project, attrs) do
    project
    |> cast(attrs, [:user_id, :name, :status, :manually_processed, :url_count])
    |> validate_required([:user_id, :name])
    |> validate_length(:name, min: 1, max: 200)
  end
end
