defmodule Seovivu.Catalog.Package do
  @moduledoc """
  A service package (quota) an admin can grant to a user. `kind` separates the
  main toolkit packages from the index-subdomain packages — both live in this
  one table, filtered by `kind`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "packages" do
    field :kind, Ecto.Enum, values: [:main, :index], default: :main
    field :name, :string
    field :credits, :integer, default: 0
    field :days, :integer, default: 0
    field :price, :decimal
    field :active, :boolean, default: true

    timestamps(type: :utc_datetime)
  end

  def changeset(package, attrs) do
    package
    |> cast(attrs, [:kind, :name, :credits, :days, :price, :active])
    |> validate_required([:kind, :name, :credits, :days])
    |> validate_number(:credits, greater_than_or_equal_to: 0)
    |> validate_number(:days, greater_than_or_equal_to: 0)
  end
end
