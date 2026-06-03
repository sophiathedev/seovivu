defmodule Seovivu.Seo.Job do
  @moduledoc """
  One batch run of a feature (e.g. "check index for 40 URLs"). Tracks live
  progress (`done`/`success_count`/`failed_count` out of `total`) and the credit
  accounting for the reserve→refund model. Each batch fans out into one
  `Seovivu.Seo.JobItem` per URL, processed concurrently by an Oban worker.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @features [:check_index, :url_status, :backlink, :redirect_301, :submit_index]
  @statuses [:running, :done, :canceled]

  schema "seo_jobs" do
    field :feature, Ecto.Enum, values: @features
    field :status, Ecto.Enum, values: @statuses, default: :running
    field :total, :integer, default: 0
    field :done, :integer, default: 0
    field :success_count, :integer, default: 0
    field :failed_count, :integer, default: 0
    field :credits_charged, :integer, default: 0
    field :credits_refunded, :integer, default: 0
    field :params, :map, default: %{}
    field :completed_at, :utc_datetime

    belongs_to :user, Seovivu.Accounts.User
    has_many :items, Seovivu.Seo.JobItem

    timestamps(type: :utc_datetime)
  end

  def features, do: @features

  def changeset(job, attrs) do
    job
    |> cast(attrs, [
      :user_id,
      :feature,
      :status,
      :total,
      :done,
      :success_count,
      :failed_count,
      :credits_charged,
      :credits_refunded,
      :params,
      :completed_at
    ])
    |> validate_required([:user_id, :feature, :total])
  end
end
