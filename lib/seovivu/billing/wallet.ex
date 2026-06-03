defmodule Seovivu.Billing.Wallet do
  @moduledoc """
  A credit pool for a user. Each user has two wallets:

    * `:main`  — credits for the SEO tools (check index, url status, etc.)
    * `:index` — a SEPARATE pool for the index.seovivu.com submit-index feature.

  `expires_at` drives the "days remaining" shown in the dashboard.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "wallets" do
    field :kind, Ecto.Enum, values: [:main, :index], default: :main
    field :credits, :integer, default: 0
    field :expires_at, :utc_datetime

    belongs_to :user, Seovivu.Accounts.User
    belongs_to :current_package, Seovivu.Catalog.Package

    has_many :ledger_entries, Seovivu.Billing.LedgerEntry

    timestamps(type: :utc_datetime)
  end

  def changeset(wallet, attrs) do
    wallet
    |> cast(attrs, [:user_id, :kind, :credits, :expires_at, :current_package_id])
    |> validate_required([:user_id, :kind])
    |> validate_number(:credits, greater_than_or_equal_to: 0)
    |> unique_constraint([:user_id, :kind])
  end

  @doc """
  Whole days remaining until `expires_at`, rounded up (0 when expired/unset).
  Rounding up means a freshly applied 10-day package reads as 10 days.
  """
  def days_remaining(%__MODULE__{expires_at: nil}, _now), do: 0

  def days_remaining(%__MODULE__{expires_at: expires_at}, now) do
    case DateTime.diff(expires_at, now, :second) do
      diff when diff <= 0 -> 0
      diff -> div(diff + 86_399, 86_400)
    end
  end
end
