defmodule Seovivu.Settings.FeatureConcurrency do
  @moduledoc """
  The maximum number of concurrent in-flight requests a single user may run for
  a given feature. This value (editable in the admin "Đa luồng" page) is read by
  `Seovivu.Settings.per_user_limit/1` and used as the `max_concurrency` of the
  `Task.async_stream` that fans a batch's URLs out in `Seovivu.Seo.run_job/1`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @features [:check_index, :submit_index, :url_status, :backlink, :redirect_301]

  schema "feature_concurrency" do
    field :feature, Ecto.Enum, values: @features
    field :per_user_limit, :integer, default: 5

    timestamps(type: :utc_datetime)
  end

  def features, do: @features

  def changeset(fc, attrs) do
    fc
    |> cast(attrs, [:feature, :per_user_limit])
    |> validate_required([:feature, :per_user_limit])
    |> validate_number(:per_user_limit, greater_than: 0, less_than_or_equal_to: 100)
    |> unique_constraint(:feature)
  end
end
