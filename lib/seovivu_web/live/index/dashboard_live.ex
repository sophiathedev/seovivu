defmodule SeovivuWeb.Index.DashboardLive do
  @moduledoc """
  Home of the Submit-Index subdomain: shows index-wallet credits, a create-project
  form, and the user's projects.
  """
  use SeovivuWeb, :live_view

  alias Seovivu.{Billing, Indexer}

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    if connected?(socket), do: Indexer.subscribe_wallet(user.id)

    {:ok,
     socket
     |> assign(:page_title, "Gửi Index")
     |> assign(:credits, index_credits(user.id))
     |> assign(:pending_count, 0)
     |> assign(:form, to_form(%{"name" => "", "urls" => ""}))
     |> assign(:projects, Indexer.list_projects(user.id))}
  end

  @impl true
  def handle_event("preview", %{"urls" => urls}, socket) do
    {:noreply, assign(socket, :pending_count, length(Indexer.parse_urls(urls)))}
  end

  def handle_event("create", %{"name" => name, "urls" => urls}, socket) do
    user = socket.assigns.current_user

    case Indexer.create_project(user, name, urls) do
      {:ok, _project} ->
        {:noreply,
         socket
         |> put_flash(:info, "Đã tạo dự án.")
         |> assign(:credits, index_credits(user.id))
         |> assign(:pending_count, 0)
         |> assign(:form, to_form(%{"name" => "", "urls" => ""}))
         |> assign(:projects, Indexer.list_projects(user.id))}

      {:error, :no_name} ->
        {:noreply, put_flash(socket, :error, "Hãy đặt tên dự án.")}

      {:error, :no_urls} ->
        {:noreply, put_flash(socket, :error, "Hãy nhập ít nhất một URL.")}

      {:error, :insufficient_credits} ->
        {:noreply, put_flash(socket, :error, "Không đủ credit Index cho dự án này.")}
    end
  end

  @impl true
  def handle_info({:wallet_updated, :index, credits}, socket) do
    {:noreply, assign(socket, :credits, credits)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.index
      current_user={@current_user}
      page_title="Gửi Index"
      flash={@flash}
      credits={@credits}
    >
      <div class="mb-6">
        <h2 class="text-3xl font-bold tracking-tight text-ink">Dự án Gửi Index</h2>
        <p class="mt-1 text-ink-muted">
          Tạo dự án để gửi URL cho Google lập chỉ mục. Mỗi URL tốn 1 credit Index.
        </p>
      </div>

      <section class="mb-8 rounded-card border border-line bg-surface p-6 shadow-card">
        <h3 class="mb-3 text-sm font-bold uppercase tracking-wider text-ink-secondary">Tạo dự án</h3>
        <.form for={@form} phx-submit="create" phx-change="preview">
          <.input
            field={@form[:name]}
            label="Tên dự án"
            placeholder="Bài viết tháng 6"
            required
          />
          <.input
            field={@form[:urls]}
            type="textarea"
            rows="6"
            label="Danh sách URL (mỗi dòng một URL)"
            placeholder="https://vidu.com/trang-1\nhttps://vidu.com/trang-2"
          />
          <div class="mt-2 flex items-center justify-between">
            <p class="text-sm text-ink-muted">
              <span class="font-semibold text-ink">{@pending_count}</span>
              URL · chi phí
              <span class="font-semibold text-ink">{Indexer.cost_for(@pending_count)}</span>
              credit
            </p>
            <.button type="submit" disabled={@pending_count == 0}>
              <.icon name="hero-paper-airplane" class="size-4" /> Gửi dự án
            </.button>
          </div>
        </.form>
      </section>

      <h3 class="mb-3 text-sm font-bold uppercase tracking-wider text-ink-secondary">
        Dự án của bạn
      </h3>
      <.table :if={@projects != []} id="my-projects" rows={@projects}>
        <:col :let={p} label="Dự án">{p.name}</:col>
        <:col :let={p} label="URL">{p.url_count}</:col>
        <:col :let={p} label="Trạng thái">
          <.badge tone={status_tone(p.status)}>{status_label(p.status)}</.badge>
        </:col>
        <:col :let={p} label="Ngày tạo">{date(p.inserted_at)}</:col>
        <:action :let={p}>
          <.link navigate={~p"/projects/#{p.id}"} class="font-semibold text-accent hover:underline">
            Chi tiết
          </.link>
        </:action>
      </.table>
      <p
        :if={@projects == []}
        class="rounded-card border border-line bg-surface px-3 py-10 text-center text-sm text-ink-muted shadow-soft"
      >
        Bạn chưa có dự án nào.
      </p>
    </Layouts.index>
    """
  end

  defp index_credits(user_id) do
    case Billing.get_wallet(user_id, :index) do
      nil -> 0
      wallet -> wallet.credits
    end
  end

  defp status_label(:submitted), do: "Đã gửi"
  defp status_label(:processing), do: "Đang xử lý"
  defp status_label(:done), do: "Hoàn tất"

  defp status_tone(:done), do: "success"
  defp status_tone(:processing), do: "info"
  defp status_tone(_), do: "neutral"
end
