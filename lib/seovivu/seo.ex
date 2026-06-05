defmodule Seovivu.Seo do
  @moduledoc """
  The SEO feature engine: batch orchestration with true cross-user concurrency.

  Each batch runs as ONE supervised task (under `Seovivu.Seo.TaskSupervisor`)
  that fans its URLs out with `Task.async_stream`, bounded by the per-user
  feature limit (`Settings.per_user_limit/1`). Because every user's batch is its
  own independent process tree, the BEAM time-slices them and no user waits on
  another — and since the work is I/O-bound (HTTP to ScrapingDog / proxies), this
  scales fine even on a single CPU.

  Credits use a reserve→refund model: `start_batch/3` reserves 1 credit per URL
  up front; `finalize_job/1` refunds the failed URLs once the batch finishes.
  Live updates are published on `"seo_job:<id>"` (`{:item_done, item}` /
  `{:job_done, job}`) and wallet changes on `"user:<id>:wallet"`.

  Tasks live in memory, so a server restart abandons in-flight batches;
  `recover_orphaned_jobs/0` (run at boot) cancels any still-`running` job and
  refunds its unfinished URLs.
  """
  import Ecto.Query, warn: false
  require Logger

  alias Seovivu.{Billing, Repo, Settings}
  alias Seovivu.Net
  alias Seovivu.Seo.{Job, JobItem}

  @pubsub Seovivu.PubSub
  @cost_per_url 1
  @max_urls 500

  # feature => its wallet (where credits are drawn from) and whether it's free.
  # Free features run without reserving/charging any credits.
  @features %{
    check_index: %{wallet: :main, free: false},
    url_status: %{wallet: :main, free: true},
    backlink: %{wallet: :main, free: true},
    redirect_301: %{wallet: :main, free: false}
  }

  @doc "Whether `feature` runs for free (no credits reserved/charged)."
  def free?(feature), do: match?(%{free: true}, Map.get(@features, feature))

  @doc "Credit cost for a batch of `count` URLs (defaults to a paid feature)."
  def cost_for(count) when is_integer(count), do: count * @cost_per_url

  @doc "Credit cost for `count` URLs of `feature` — zero for free features."
  def cost_for(feature, count) when is_atom(feature) and is_integer(count) do
    if free?(feature), do: 0, else: cost_for(count)
  end

  @doc "Max URLs accepted in a single batch."
  def max_urls, do: @max_urls

  @doc """
  Parses a textarea blob (or list) into a clean, de-duplicated URL list, capped
  at `max_urls/0`.
  """
  def parse_urls(text) when is_binary(text),
    do: text |> String.split(["\n", "\r\n"]) |> parse_urls()

  def parse_urls(lines) when is_list(lines) do
    lines
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> Enum.take(@max_urls)
  end

  @doc """
  Starts a feature batch for `user` over `urls`. Reserves credits, persists the
  job + items, then (unless `:seo_async` is disabled) kicks off the runner task.
  Returns `{:ok, job}` or `{:error, :no_urls | :insufficient_credits |
  :unknown_feature}`.
  """
  def start_batch(user, feature, urls, params \\ %{}) do
    with {:ok, spec} <- fetch_spec(feature),
         clean = parse_urls(urls),
         {:ok, _} <- ensure_nonempty(clean),
         cost = cost_for(feature, length(clean)),
         wallet = Billing.get_wallet(user.id, spec.wallet),
         {:ok, _wallet} <- reserve(wallet, cost, feature) do
      {:ok, job} = insert_job(user.id, feature, clean, cost, params)
      if cost > 0, do: broadcast_wallet(user.id, spec.wallet)
      maybe_run(job)
      {:ok, job}
    end
  end

  defp fetch_spec(feature) do
    case Map.fetch(@features, feature) do
      {:ok, spec} -> {:ok, spec}
      :error -> {:error, :unknown_feature}
    end
  end

  defp ensure_nonempty([]), do: {:error, :no_urls}
  defp ensure_nonempty(_), do: {:ok, :ok}

  # Free features (cost 0) run even without a main wallet.
  defp reserve(_wallet, 0, _feature), do: {:ok, :free}
  defp reserve(nil, _cost, _feature), do: {:error, :insufficient_credits}
  defp reserve(wallet, cost, feature), do: Billing.reserve(wallet, cost, feature)

  defp insert_job(user_id, feature, urls, cost, params) do
    now = now()

    Repo.transaction(fn ->
      job =
        %Job{}
        |> Job.changeset(%{
          user_id: user_id,
          feature: feature,
          total: length(urls),
          credits_charged: cost,
          params: params
        })
        |> Repo.insert!()

      rows =
        Enum.map(urls, fn url ->
          %{
            job_id: job.id,
            url: url,
            status: :pending,
            result: %{},
            inserted_at: now,
            updated_at: now
          }
        end)

      Repo.insert_all(JobItem, rows)
      job
    end)
  end

  ## Execution

  # In tests we disable auto-running so batches don't spawn real HTTP work;
  # tests drive `record_item/3` + `finalize_job/1` directly.
  defp maybe_run(job) do
    if Application.get_env(:seovivu, :seo_async, true) do
      Task.Supervisor.start_child(Seovivu.Seo.TaskSupervisor, fn -> run_job(job) end)
    end

    :ok
  end

  @doc """
  Runs every item of `job` concurrently (bounded by the per-user limit), then
  finalizes. Safe to call directly (e.g. in a synchronous context).
  """
  def run_job(%Job{} = job) do
    limit = max(1, Settings.per_user_limit(job.feature))

    job.id
    |> list_items()
    |> Task.async_stream(fn item -> process_item(item, job) end,
      max_concurrency: limit,
      timeout: :infinity,
      ordered: false
    )
    |> Stream.run()

    finalize_job(job)
  end

  # Processes one URL: runs the feature, persists + broadcasts the item result.
  defp process_item(item, %Job{} = job) do
    {status, fields} =
      try do
        feature_runner().(job.feature, item, job.params || %{})
      rescue
        error ->
          Logger.error("SEO item #{item.id} crashed: #{Exception.message(error)}")
          {:failed, %{result: %{"error" => "exception"}}}
      end

    record_item(item, status, fields)
  end

  # The per-URL feature executor. Overridable (tests inject a fake to avoid real
  # HTTP); defaults to the real `run_feature/3`.
  defp feature_runner do
    Application.get_env(:seovivu, :seo_feature_runner, &run_feature/3)
  end

  defp run_feature(:check_index, item, _params) do
    case Net.Client.check_index(item.url) do
      {:ok, %{indexed: indexed, http_status: status}} ->
        {:success, %{result: %{"indexed" => indexed, "http_status" => status}}}

      {:error, reason} ->
        {:failed, %{result: %{"error" => inspect(reason)}}}
    end
  end

  defp run_feature(:url_status, item, _params) do
    case Net.Client.url_status(item.url) do
      {:ok, %{http_status: status, ok: ok, latency_ms: latency, proxy_id: proxy_id}} ->
        {:success,
         %{
           result: %{"http_status" => status, "ok" => ok},
           latency_ms: latency,
           proxy_id: proxy_id
         }}

      error ->
        proxied_failure(error)
    end
  end

  defp run_feature(:backlink, item, params) do
    target = params["target"] || ""

    case Net.Client.fetch_body(item.url) do
      {:ok, %{body: body, http_status: status, latency_ms: latency, proxy_id: proxy_id}} ->
        anchors = Net.Client.find_backlinks(body, target)

        {:success,
         %{
           result: %{
             "found" => anchors != [],
             "count" => length(anchors),
             "anchors" => anchors,
             "http_status" => status,
             "target" => target
           },
           latency_ms: latency,
           proxy_id: proxy_id
         }}

      error ->
        proxied_failure(error)
    end
  end

  defp run_feature(:redirect_301, item, _params) do
    case Net.Client.redirect_status(item.url) do
      {:ok,
       %{
         http_status: status,
         location: location,
         redirect: redirect,
         latency_ms: latency,
         proxy_id: proxy_id
       }} ->
        {:success,
         %{
           result: %{"http_status" => status, "location" => location, "redirect" => redirect},
           latency_ms: latency,
           proxy_id: proxy_id
         }}

      error ->
        proxied_failure(error)
    end
  end

  # Normalizes the two proxied-error shapes into a failed item.
  defp proxied_failure({:error, :no_proxy}),
    do: {:failed, %{result: %{"error" => "no_proxy"}}}

  defp proxied_failure({:error, reason, proxy_id}),
    do: {:failed, %{result: %{"error" => inspect(reason)}, proxy_id: proxy_id}}

  @doc """
  Persists one item's terminal outcome (`:success`/`:failed`) and broadcasts
  `{:item_done, item}` for live progress. Returns the item's status.
  """
  def record_item(%JobItem{} = item, status, fields) when status in [:success, :failed] do
    updated =
      item
      |> JobItem.result_changeset(Map.put(fields, :status, status))
      |> Repo.update!()

    broadcast(item.job_id, {:item_done, updated})
    status
  end

  @doc """
  Finalizes a job: tallies item outcomes, refunds the failed URLs, marks the job
  done, and broadcasts `{:job_done, job}`.
  """
  def finalize_job(%Job{} = job) do
    counts = item_counts(job.id)
    success = Map.get(counts, :success, 0)
    failed = Map.get(counts, :failed, 0)
    refund_credits(job, failed)
    refunded = if free?(job.feature), do: 0, else: failed

    {:ok, job} =
      job
      |> Job.changeset(%{
        status: :done,
        done: success + failed,
        success_count: success,
        failed_count: failed,
        credits_refunded: refunded,
        completed_at: now()
      })
      |> Repo.update()

    broadcast(job.id, {:job_done, job})
    job
  end

  defp refund_credits(_job, 0), do: :ok

  defp refund_credits(job, amount) do
    if free?(job.feature) do
      :ok
    else
      do_refund_credits(job, amount)
    end
  end

  defp do_refund_credits(job, amount) do
    spec = Map.fetch!(@features, job.feature)

    case Billing.get_wallet(job.user_id, spec.wallet) do
      nil -> :ok
      wallet -> Billing.refund(wallet, amount, job.feature)
    end

    broadcast_wallet(job.user_id, spec.wallet)
  end

  defp item_counts(job_id) do
    JobItem
    |> where(job_id: ^job_id)
    |> group_by([i], i.status)
    |> select([i], {i.status, count(i.id)})
    |> Repo.all()
    |> Map.new()
  end

  ## Restart recovery

  @doc """
  Cancels jobs left `running` by a previous server lifetime and refunds the
  credits reserved for their still-unfinished URLs. Run once at boot.
  """
  def recover_orphaned_jobs do
    orphans = Repo.all(from j in Job, where: j.status == :running)
    Enum.each(orphans, &cancel_orphan/1)
    if orphans != [], do: Logger.info("Recovered #{length(orphans)} orphaned SEO job(s).")
    :ok
  end

  defp cancel_orphan(%Job{} = job) do
    unfinished =
      JobItem
      |> where([i], i.job_id == ^job.id and i.status in [:pending, :running])
      |> Repo.aggregate(:count)

    if Map.has_key?(@features, job.feature), do: refund_credits(job, unfinished)
    refunded = if free?(job.feature), do: 0, else: unfinished

    job
    |> Job.changeset(%{
      status: :canceled,
      credits_refunded: (job.credits_refunded || 0) + refunded,
      completed_at: now()
    })
    |> Repo.update()
  end

  ## Queries

  @doc "Recent jobs for a user filtered by feature, newest first."
  def list_jobs(user_id, feature, limit \\ 20) do
    Job
    |> where(user_id: ^user_id, feature: ^feature)
    |> order_by(desc: :id)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc "Recent jobs for a user across all features, newest first."
  def list_recent_jobs(user_id, limit \\ 30) do
    Job
    |> where(user_id: ^user_id)
    |> order_by(desc: :id)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Per-feature usage totals for a user:
  `%{feature => %{jobs, urls, success, failed}}`.
  """
  def usage_summary(user_id) do
    Job
    |> where(user_id: ^user_id)
    |> group_by([j], j.feature)
    |> select([j], {
      j.feature,
      %{
        jobs: count(j.id),
        urls: coalesce(sum(j.total), 0),
        success: coalesce(sum(j.success_count), 0),
        failed: coalesce(sum(j.failed_count), 0)
      }
    })
    |> Repo.all()
    |> Map.new()
  end

  @doc "Items of a job, ordered by id."
  def list_items(job_id) do
    JobItem |> where(job_id: ^job_id) |> order_by(:id) |> Repo.all()
  end

  @doc "Loads a job scoped to its owner (nil if not theirs)."
  def get_user_job(user_id, id) do
    Job |> where(id: ^id, user_id: ^user_id) |> Repo.one()
  end

  def get_job!(id), do: Repo.get!(Job, id)
  def get_item!(id), do: Repo.get!(JobItem, id)

  @doc "System-wide usage per feature (all users): `%{feature => %{jobs, urls, success, failed}}`."
  def global_usage do
    Job
    |> group_by([j], j.feature)
    |> select([j], {
      j.feature,
      %{
        jobs: count(j.id),
        urls: coalesce(sum(j.total), 0),
        success: coalesce(sum(j.success_count), 0),
        failed: coalesce(sum(j.failed_count), 0)
      }
    })
    |> Repo.all()
    |> Map.new()
  end

  ## PubSub

  @doc "Subscribes the caller to a job's live progress."
  def subscribe(job_id), do: Phoenix.PubSub.subscribe(@pubsub, "seo_job:#{job_id}")

  @doc "Subscribes the caller to a user's wallet changes."
  def subscribe_wallet(user_id), do: Phoenix.PubSub.subscribe(@pubsub, "user:#{user_id}:wallet")

  defp broadcast(job_id, message),
    do: Phoenix.PubSub.broadcast(@pubsub, "seo_job:#{job_id}", message)

  defp broadcast_wallet(user_id, kind) do
    credits =
      case Billing.get_wallet(user_id, kind) do
        nil -> 0
        wallet -> wallet.credits
      end

    Phoenix.PubSub.broadcast(@pubsub, "user:#{user_id}:wallet", {:wallet_updated, kind, credits})
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
