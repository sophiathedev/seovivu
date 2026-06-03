defmodule SeovivuWeb.BatchFeature do
  @moduledoc """
  Shared LiveView behaviour for the batch check tools (Check Index, URL Status,
  …). Injects the common lifecycle — wallet/credit assigns, the URL textarea
  form with a live cost preview, kicking off a batch, and applying live progress
  from PubSub (`{:item_done, _}`, `{:job_done, _}`, `{:wallet_updated, …}`).

  Each feature LiveView supplies only its `render/1` (and feature-specific result
  rendering):

      use SeovivuWeb.BatchFeature, feature: :check_index, title: "Kiểm tra Index"
  """
  use Phoenix.Component

  import Phoenix.LiveView
  import SeovivuWeb.CoreComponents
  import SeovivuWeb.DashboardComponents

  alias Seovivu.Seo

  defmacro __using__(opts) do
    feature = Keyword.fetch!(opts, :feature)
    title = Keyword.fetch!(opts, :title)

    quote do
      use SeovivuWeb, :live_view

      alias Seovivu.{Billing, Repo, Seo}
      alias SeovivuWeb.BatchFeature

      @feature unquote(feature)
      @title unquote(title)

      @impl true
      def mount(_params, _session, socket) do
        user = socket.assigns.current_user
        main = user.id |> Billing.get_wallet(:main) |> Repo.preload(:current_package)
        if connected?(socket), do: Seo.subscribe_wallet(user.id)

        {:ok,
         socket
         |> assign(:page_title, @title)
         |> assign(:credits, BatchFeature.credits(main))
         |> assign(:days, BatchFeature.days(main))
         |> assign(:tier, BatchFeature.tier(main))
         |> assign(:job, nil)
         |> assign(:pending_count, 0)
         |> assign(:form, to_form(%{"urls" => ""}))
         |> stream(:items, [])}
      end

      @impl true
      def handle_event("preview", params, socket) do
        urls = Map.get(params, "urls", "")
        {:noreply, assign(socket, :pending_count, length(Seo.parse_urls(urls)))}
      end

      def handle_event("run", params, socket) do
        BatchFeature.run_batch(socket, @feature, params)
      end

      @impl true
      def handle_info({:item_done, item}, socket) do
        {:noreply, BatchFeature.apply_item(socket, item)}
      end

      def handle_info({:job_done, job}, socket) do
        {:noreply, assign(socket, :job, job)}
      end

      def handle_info({:wallet_updated, :main, credits}, socket) do
        {:noreply, assign(socket, :credits, credits)}
      end

      def handle_info(_message, socket), do: {:noreply, socket}
    end
  end

  ## Shared runtime helpers

  @doc "Starts a batch from the submitted form params and wires up live progress."
  def run_batch(socket, feature, params) do
    urls = Map.get(params, "urls", "")
    extra = Map.drop(params, ["urls", "_target", "_csrf_token"])

    case Seo.start_batch(socket.assigns.current_user, feature, urls, extra) do
      {:ok, job} ->
        Seo.subscribe(job.id)

        {:noreply,
         socket
         |> assign(:job, job)
         |> assign(:pending_count, 0)
         |> assign(:form, to_form(%{"urls" => ""}))
         |> stream(:items, Seo.list_items(job.id), reset: true)}

      {:error, :no_urls} ->
        {:noreply, put_flash(socket, :error, "Hãy nhập ít nhất một URL.")}

      {:error, :insufficient_credits} ->
        {:noreply, put_flash(socket, :error, "Không đủ credit cho lô này.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Không khởi tạo được tác vụ. Vui lòng thử lại.")}
    end
  end

  @doc "Applies one finished item: bumps the progress counters and updates its row."
  def apply_item(socket, item) do
    socket
    |> update(:job, &bump(&1, item.status))
    |> stream_insert(:items, item)
  end

  defp bump(%{} = job, :success),
    do: %{job | done: job.done + 1, success_count: job.success_count + 1}

  defp bump(%{} = job, :failed),
    do: %{job | done: job.done + 1, failed_count: job.failed_count + 1}

  defp bump(job, _), do: job

  def credits(nil), do: 0
  def credits(%{credits: credits}), do: credits

  def days(nil), do: 0
  def days(wallet), do: Seovivu.Billing.days_remaining(wallet)

  def tier(%{current_package: %{name: name}}), do: name
  def tier(_), do: "Miễn phí"

  ## Shared UI

  @doc "The URL textarea + submit card with a live cost preview."
  attr :form, :map, required: true
  attr :pending_count, :integer, default: 0
  attr :running, :boolean, default: false
  attr :submit_label, :string, default: "Bắt đầu kiểm tra"
  attr :placeholder, :string, default: "https://vidu.com/trang-1\nhttps://vidu.com/trang-2"
  slot :extra, doc: "optional fields rendered above the URL textarea"

  def url_form(assigns) do
    ~H"""
    <section class="rounded-card border border-line bg-surface p-6 shadow-card">
      <.form for={@form} phx-submit="run" phx-change="preview">
        {render_slot(@extra)}
        <.input
          field={@form[:urls]}
          type="textarea"
          label="Danh sách URL (mỗi dòng một URL)"
          rows="8"
          placeholder={@placeholder}
        />
        <div class="mt-2 flex items-center justify-between">
          <p class="text-sm text-ink-muted">
            <span class="font-semibold text-ink">{@pending_count}</span>
            URL · chi phí
            <span class="font-semibold text-ink">{Seovivu.Seo.cost_for(@pending_count)}</span>
            credit
          </p>
          <.button type="submit" disabled={@running or @pending_count == 0}>
            <.icon name="hero-play" class="size-4" /> {@submit_label}
          </.button>
        </div>
      </.form>
    </section>
    """
  end

  @doc "Progress bar + success/failed tallies for a running/finished job."
  attr :job, :map, required: true

  def progress(assigns) do
    assigns = assign(assigns, :percent, percent(assigns.job))

    ~H"""
    <section class="rounded-card border border-line bg-surface p-6 shadow-card">
      <div class="mb-3 flex items-center justify-between gap-3">
        <div class="flex items-center gap-2">
          <h3 class="text-sm font-bold uppercase tracking-wider text-ink-secondary">Tiến độ</h3>
          <.badge :if={@job.status == :running} tone="info">đang chạy</.badge>
          <.badge :if={@job.status == :done} tone="success">hoàn tất</.badge>
        </div>
        <p class="text-sm text-ink-muted">
          {@job.done}/{@job.total} ·
          <span class="font-semibold text-success">{@job.success_count} thành công</span>
          · <span class="font-semibold text-danger">{@job.failed_count} lỗi</span>
        </p>
      </div>
      <div class="h-2.5 w-full overflow-hidden rounded-full bg-page">
        <div
          class="h-full rounded-full bg-brand transition-all duration-300"
          style={"width: #{@percent}%"}
        >
        </div>
      </div>
    </section>
    """
  end

  defp percent(%{total: total}) when total in [0, nil], do: 0
  defp percent(%{done: done, total: total}), do: round(done / total * 100)

  @doc "A small status pill for one job item (pending / done / failed)."
  attr :status, :atom, required: true

  def status_badge(%{status: :failed} = assigns), do: ~H|<.badge tone="danger">Lỗi</.badge>|
  def status_badge(%{status: :success} = assigns), do: ~H|<.badge tone="success">Xong</.badge>|
  def status_badge(assigns), do: ~H|<.badge tone="neutral">Đang chờ</.badge>|
end
