defmodule SeovivuWeb.Admin.IndexProjectsLive do
  @moduledoc """
  Admin review of Submit-Index projects: filter by status/name, advance status,
  toggle the manually-processed flag, and delete.
  """
  use SeovivuWeb, :live_view

  alias Seovivu.Indexer

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Dự án Gửi Index")
     |> assign(:status, nil)
     |> assign(:search, "")
     |> load()}
  end

  defp load(socket) do
    socket
    |> assign(
      :projects,
      Indexer.list_projects_admin(status: socket.assigns.status, search: socket.assigns.search)
    )
    |> assign(:stats, Indexer.stats())
  end

  @impl true
  def handle_event("filter", %{"status" => status}, socket) do
    {:noreply, socket |> assign(:status, parse_status(status)) |> load()}
  end

  def handle_event("search", %{"q" => q}, socket) do
    {:noreply, socket |> assign(:search, q) |> load()}
  end

  def handle_event("set_status", %{"_id" => id, "status" => status}, socket) do
    id |> Indexer.get_project!() |> Indexer.set_status(parse_status(status))
    {:noreply, socket |> put_flash(:info, "Đã cập nhật trạng thái.") |> load()}
  end

  def handle_event("toggle", %{"id" => id}, socket) do
    id |> Indexer.get_project!() |> Indexer.toggle_manually_processed()
    {:noreply, load(socket)}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    id |> Indexer.get_project!() |> Indexer.delete_project()
    {:noreply, socket |> put_flash(:info, "Đã xóa dự án.") |> load()}
  end

  defp parse_status("submitted"), do: :submitted
  defp parse_status("processing"), do: :processing
  defp parse_status("done"), do: :done
  defp parse_status(_), do: nil

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin
      current_user={@current_user}
      active={:index_projects}
      page_title="Dự án Gửi Index"
      flash={@flash}
    >
      <div class="mb-6">
        <h2 class="text-3xl font-bold tracking-tight text-ink">Dự án Gửi Index</h2>
        <p class="mt-1 text-ink-muted">Duyệt và xử lý các dự án người dùng gửi để index.</p>
      </div>

      <div class="mb-6 grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <.stat_card
          icon="hero-rectangle-stack"
          tone="info"
          label="Tổng dự án"
          value={to_string(@stats.projects)}
        />
        <.stat_card icon="hero-link" tone="neutral" label="Tổng URL" value={to_string(@stats.urls)} />
        <.stat_card
          icon="hero-clock"
          tone="warning"
          label="Chờ xử lý"
          value={
            to_string(
              Map.get(@stats.by_status, :submitted, 0) + Map.get(@stats.by_status, :processing, 0)
            )
          }
        />
        <.stat_card
          icon="hero-check-circle"
          tone="success"
          label="Hoàn tất"
          value={to_string(Map.get(@stats.by_status, :done, 0))}
        />
      </div>

      <div class="mb-4 flex flex-wrap items-center gap-3">
        <form phx-change="filter">
          <select
            name="status"
            class="rounded-button border border-line bg-surface px-3 py-2 text-sm text-ink shadow-soft focus:border-accent focus:outline-none focus:ring-2 focus:ring-accent/30"
          >
            <option value="" selected={is_nil(@status)}>Tất cả trạng thái</option>
            <option value="submitted" selected={@status == :submitted}>Đã gửi</option>
            <option value="processing" selected={@status == :processing}>Đang xử lý</option>
            <option value="done" selected={@status == :done}>Hoàn tất</option>
          </select>
        </form>
        <form phx-change="search" phx-submit="search" class="w-64">
          <input
            name="q"
            value={@search}
            placeholder="Tìm theo tên dự án"
            class="block w-full rounded-button border border-line bg-surface px-3 py-2 text-sm text-ink shadow-soft placeholder:text-ink-light focus:border-accent focus:outline-none focus:ring-2 focus:ring-accent/30"
          />
        </form>
      </div>

      <.table :if={@projects != []} id="index-projects" rows={@projects}>
        <:col :let={p} label="ID">{p.id}</:col>
        <:col :let={p} label="Người dùng">
          {(p.user && (p.user.username || p.user.telegram_first_name)) || "-"}
        </:col>
        <:col :let={p} label="Dự án">
          <div class="flex items-center gap-2">
            <span class="font-semibold text-ink">{p.name}</span>
            <.badge :if={p.manually_processed} tone="warning">thủ công</.badge>
          </div>
        </:col>
        <:col :let={p} label="URL">{p.url_count}</:col>
        <:col :let={p} label="Trạng thái">
          <form phx-change="set_status">
            <input type="hidden" name="_id" value={p.id} />
            <select
              name="status"
              class="rounded-button border border-line bg-surface px-2 py-1.5 text-sm text-ink shadow-soft focus:border-accent focus:outline-none focus:ring-2 focus:ring-accent/30"
            >
              <option value="submitted" selected={p.status == :submitted}>Đã gửi</option>
              <option value="processing" selected={p.status == :processing}>Đang xử lý</option>
              <option value="done" selected={p.status == :done}>Hoàn tất</option>
            </select>
          </form>
        </:col>
        <:col :let={p} label="Ngày tạo">{date(p.inserted_at)}</:col>
        <:action :let={p}>
          <.link phx-click="toggle" phx-value-id={p.id} class="text-accent hover:underline">
            {if p.manually_processed, do: "Bỏ TC", else: "Đánh TC"}
          </.link>
        </:action>
        <:action :let={p}>
          <.link
            phx-click="delete"
            phx-value-id={p.id}
            data-confirm="Xóa dự án này?"
            class="text-danger hover:underline"
          >
            Xóa
          </.link>
        </:action>
      </.table>

      <p
        :if={@projects == []}
        class="rounded-card border border-line bg-surface px-3 py-10 text-center text-sm text-ink-muted shadow-soft"
      >
        Không có dự án phù hợp.
      </p>
    </Layouts.admin>
    """
  end
end
