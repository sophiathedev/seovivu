defmodule Seovivu.Seo.JobItem do
  @moduledoc """
  A single URL within a `Seovivu.Seo.Job`. This row is also the per-feature usage
  log: it records the outcome (`result` map), which proxy egressed the request,
  and the latency. The unit of concurrent work — one Oban job processes one item.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @statuses [:pending, :running, :success, :failed]

  schema "seo_job_items" do
    field :url, :string
    field :status, Ecto.Enum, values: @statuses, default: :pending
    field :result, :map, default: %{}
    field :latency_ms, :integer

    belongs_to :job, Seovivu.Seo.Job
    belongs_to :proxy, Seovivu.Net.Proxy

    timestamps(type: :utc_datetime)
  end

  def changeset(item, attrs) do
    item
    |> cast(attrs, [:job_id, :url, :status, :result, :latency_ms, :proxy_id])
    |> validate_required([:job_id, :url])
  end

  @doc "Changeset recording the terminal outcome of processing the item."
  def result_changeset(item, attrs) do
    cast(item, attrs, [:status, :result, :latency_ms, :proxy_id])
  end
end
