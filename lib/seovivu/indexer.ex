defmodule Seovivu.Indexer do
  @moduledoc """
  The "Submit Index" subdomain (index.seovivu.com): users create projects — named
  batches of URLs to push to Google for indexing — billed against the SEPARATE
  `:index` credit wallet (1 credit per URL, reserved on creation).

  Projects are processed by an admin (there is no free programmatic Google
  indexing API): the admin review UI toggles `manually_processed`, advances
  `status` (submitted → processing → done), and can bulk-update or delete.
  """
  import Ecto.Query, warn: false

  alias Seovivu.{Billing, Repo}
  alias Seovivu.Indexer.{Project, ProjectUrl}

  @pubsub Seovivu.PubSub
  @cost_per_url 1
  @max_urls 500
  @wallet_kind :index

  @doc "Credit cost (from the index wallet) for `count` URLs."
  def cost_for(count) when is_integer(count), do: count * @cost_per_url

  def max_urls, do: @max_urls

  @doc "Parses a textarea blob into a clean, de-duplicated, capped URL list."
  def parse_urls(text) when is_binary(text) do
    text
    |> String.split(["\n", "\r\n"])
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> Enum.take(@max_urls)
  end

  def parse_urls(_), do: []

  @doc """
  Creates a project for `user`: reserves index credits, persists the project and
  its URLs. Returns `{:ok, project}` or
  `{:error, :no_name | :no_urls | :insufficient_credits}`.
  """
  def create_project(user, name, urls_text) do
    name = String.trim(name || "")
    urls = parse_urls(urls_text)

    cond do
      name == "" ->
        {:error, :no_name}

      urls == [] ->
        {:error, :no_urls}

      true ->
        cost = cost_for(length(urls))
        wallet = Billing.get_wallet(user.id, @wallet_kind)

        case reserve(wallet, cost) do
          {:ok, _wallet} ->
            project = insert_project(user.id, name, urls)
            broadcast_wallet(user.id)
            {:ok, project}

          error ->
            error
        end
    end
  end

  defp reserve(nil, _cost), do: {:error, :insufficient_credits}
  defp reserve(wallet, cost), do: Billing.reserve(wallet, cost, :submit_index)

  defp insert_project(user_id, name, urls) do
    now = now()

    Repo.transaction(fn ->
      project =
        %Project{}
        |> Project.changeset(%{user_id: user_id, name: name, url_count: length(urls)})
        |> Repo.insert!()

      rows =
        Enum.map(urls, fn url ->
          %{project_id: project.id, url: url, status: :pending, inserted_at: now, updated_at: now}
        end)

      Repo.insert_all(ProjectUrl, rows)
      project
    end)
    |> case do
      {:ok, project} -> project
    end
  end

  ## User queries

  def list_projects(user_id) do
    Project |> where(user_id: ^user_id) |> order_by(desc: :id) |> Repo.all()
  end

  def get_project!(id), do: Repo.get!(Project, id)

  @doc "Loads a project scoped to a user (nil if not theirs), with URLs preloaded."
  def get_user_project(user_id, id) do
    Project
    |> where(id: ^id, user_id: ^user_id)
    |> preload(:urls)
    |> Repo.one()
  end

  def list_project_urls(project_id) do
    ProjectUrl |> where(project_id: ^project_id) |> order_by(:id) |> Repo.all()
  end

  def count_projects(user_id), do: Project |> where(user_id: ^user_id) |> Repo.aggregate(:count)

  ## Admin

  @doc """
  Lists projects for admin review with `:status` / `:search` filters and paging,
  user preloaded.
  """
  def list_projects_admin(opts \\ []) do
    Project
    |> filter_status(Keyword.get(opts, :status))
    |> filter_search(Keyword.get(opts, :search))
    |> order_by(desc: :id)
    |> limit(^Keyword.get(opts, :limit, 50))
    |> offset(^Keyword.get(opts, :offset, 0))
    |> Repo.all()
    |> Repo.preload(:user)
  end

  defp filter_status(query, status) when status in [:submitted, :processing, :done],
    do: where(query, status: ^status)

  defp filter_status(query, _), do: query

  defp filter_search(query, term) when is_binary(term) and term != "",
    do: where(query, [p], ilike(p.name, ^"%#{term}%"))

  defp filter_search(query, _), do: query

  def set_status(%Project{} = project, status) when status in [:submitted, :processing, :done] do
    project |> Project.changeset(%{status: status}) |> Repo.update()
  end

  def toggle_manually_processed(%Project{} = project) do
    project
    |> Project.changeset(%{manually_processed: !project.manually_processed})
    |> Repo.update()
  end

  @doc "Bulk-sets the status of many projects by id. Returns the updated count."
  def bulk_set_status(ids, status)
      when is_list(ids) and status in [:submitted, :processing, :done] do
    {count, _} =
      Project
      |> where([p], p.id in ^ids)
      |> Repo.update_all(set: [status: status, updated_at: now()])

    count
  end

  def delete_project(%Project{} = project), do: Repo.delete(project)

  def delete_projects(ids) when is_list(ids) do
    {count, _} = Project |> where([p], p.id in ^ids) |> Repo.delete_all()
    count
  end

  @doc "Aggregate stats for the admin overview: total projects/urls + by-status counts."
  def stats do
    by_status =
      Project
      |> group_by([p], p.status)
      |> select([p], {p.status, count(p.id)})
      |> Repo.all()
      |> Map.new()

    %{
      projects: Repo.aggregate(Project, :count),
      urls: Repo.aggregate(Project, :sum, :url_count) || 0,
      by_status: by_status
    }
  end

  ## Helpers

  @doc "Subscribes the caller to a user's wallet changes."
  def subscribe_wallet(user_id), do: Phoenix.PubSub.subscribe(@pubsub, "user:#{user_id}:wallet")

  defp broadcast_wallet(user_id) do
    credits =
      case Billing.get_wallet(user_id, @wallet_kind) do
        nil -> 0
        wallet -> wallet.credits
      end

    Phoenix.PubSub.broadcast(
      @pubsub,
      "user:#{user_id}:wallet",
      {:wallet_updated, @wallet_kind, credits}
    )
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
