defmodule Seovivu.Billing.LedgerEntry do
  @moduledoc """
  An immutable audit record of every credit movement on a wallet.

  `delta` is positive for grants (purchase/admin/refund) and negative for spend.
  The reserve→refund flow records a negative `:feature_spend` on batch start and
  a positive `:refund` for URLs that failed or never ran.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "ledger_entries" do
    field :delta, :integer

    field :reason, Ecto.Enum,
      values: [:purchase, :admin_adjust, :feature_spend, :refund, :upgrade, :expiry]

    field :feature, :string
    field :meta, :map, default: %{}

    belongs_to :wallet, Seovivu.Billing.Wallet

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:wallet_id, :delta, :reason, :feature, :meta])
    |> validate_required([:wallet_id, :delta, :reason])
  end
end
