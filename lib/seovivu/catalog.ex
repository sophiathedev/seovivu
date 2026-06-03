defmodule Seovivu.Catalog do
  @moduledoc "Service packages (quotas) for the main toolkit and the index subdomain."
  import Ecto.Query, warn: false

  alias Seovivu.Repo
  alias Seovivu.Catalog.Package

  @doc "Lists packages of the given `kind` (`:main` or `:index`)."
  def list_packages(kind) do
    Package |> where(kind: ^kind) |> order_by([:name]) |> Repo.all()
  end

  def get_package!(id), do: Repo.get!(Package, id)

  def change_package(%Package{} = package, attrs \\ %{}), do: Package.changeset(package, attrs)

  def create_package(attrs) do
    %Package{} |> Package.changeset(attrs) |> Repo.insert()
  end

  def update_package(%Package{} = package, attrs) do
    package |> Package.changeset(attrs) |> Repo.update()
  end

  def delete_package(%Package{} = package), do: Repo.delete(package)
end
