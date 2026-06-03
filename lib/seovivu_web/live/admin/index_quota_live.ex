defmodule SeovivuWeb.Admin.IndexQuotaLive do
  @moduledoc "Admin page: CRUD for index-subdomain packages (kind=:index)."
  use SeovivuWeb, :live_view

  alias Seovivu.Catalog
  alias Seovivu.Catalog.Package

  @kind :index

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Gói Gửi Index")
     |> assign(:editing_id, nil)
     |> assign(:open, false)
     |> load()}
  end

  defp load(socket) do
    socket
    |> assign(:packages, Catalog.list_packages(@kind))
    |> assign_form(Catalog.change_package(%Package{kind: @kind}))
  end

  defp assign_form(socket, changeset), do: assign(socket, :form, to_form(changeset))

  @impl true
  def handle_event("edit", %{"id" => id}, socket) do
    package = Catalog.get_package!(id)

    {:noreply,
     socket
     |> assign(:editing_id, package.id)
     |> assign(:open, true)
     |> assign_form(Catalog.change_package(package))}
  end

  def handle_event("new", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing_id, nil)
     |> assign(:open, true)
     |> assign_form(Catalog.change_package(%Package{kind: @kind}))}
  end

  def handle_event("close", _params, socket) do
    {:noreply, socket |> assign(:open, false) |> assign(:editing_id, nil)}
  end

  def handle_event("save", %{"package" => params}, socket) do
    params = Map.put(params, "kind", to_string(@kind))

    result =
      case socket.assigns.editing_id do
        nil -> Catalog.create_package(params)
        id -> id |> Catalog.get_package!() |> Catalog.update_package(params)
      end

    case result do
      {:ok, _package} ->
        {:noreply,
         socket
         |> put_flash(:info, "Đã lưu gói.")
         |> assign(:open, false)
         |> assign(:editing_id, nil)
         |> load()}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    id |> Catalog.get_package!() |> Catalog.delete_package()

    {:noreply,
     socket
     |> put_flash(:info, "Đã xóa gói.")
     |> assign(:open, false)
     |> assign(:editing_id, nil)
     |> load()}
  end

  def handle_event("toggle_active", %{"id" => id}, socket) do
    package = Catalog.get_package!(id)
    {:ok, _} = Catalog.update_package(package, %{active: !package.active})
    {:noreply, load(socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin
      current_user={@current_user}
      active={:index_quota}
      page_title="Gói Gửi Index"
      flash={@flash}
    >
      <div class="mb-6 flex flex-wrap items-end justify-between gap-4">
        <div>
          <h2 class="text-3xl font-bold tracking-tight text-ink">Gói Gửi Index</h2>
          <p class="mt-1 text-ink-muted">Các gói credit cho dịch vụ Gửi Index (ví riêng).</p>
        </div>
        <.button variant="primary" phx-click="new">
          <.icon name="hero-plus" class="size-4" /> Tạo gói mới
        </.button>
      </div>

      <.table :if={@packages != []} id="index-packages" rows={@packages}>
        <:col :let={p} label="Tên">{p.name}</:col>
        <:col :let={p} label="Số credit">{p.credits}</:col>
        <:col :let={p} label="Số ngày">{p.days}</:col>
        <:col :let={p} label="Giá">{p.price || "-"}</:col>
        <:col :let={p} label="Trạng thái">
          <.toggle on={p.active} on_click="toggle_active" id={p.id} />
        </:col>
        <:action :let={p}>
          <.link
            phx-click="edit"
            phx-value-id={p.id}
            class="font-semibold text-accent hover:underline"
          >
            Sửa
          </.link>
        </:action>
        <:action :let={p}>
          <.link
            phx-click="delete"
            phx-value-id={p.id}
            data-confirm="Xóa gói này?"
            class="text-danger hover:underline"
          >
            Xóa
          </.link>
        </:action>
      </.table>

      <p
        :if={@packages == []}
        class="rounded-card border border-line bg-surface px-3 py-10 text-center text-sm text-ink-muted shadow-soft"
      >
        Chưa có gói nào. Nhấn "Tạo gói mới" để bắt đầu.
      </p>

      <.package_panel :if={@open} form={@form} editing_id={@editing_id} />
    </Layouts.admin>
    """
  end

  attr :form, :map, required: true
  attr :editing_id, :any, required: true

  defp package_panel(assigns) do
    ~H"""
    <div class="fixed inset-0 z-40 flex justify-end bg-ink/30" phx-click="close">
      <div
        class="h-full w-full max-w-md overflow-y-auto bg-surface p-6 shadow-card"
        onclick="event.stopPropagation()"
      >
        <div class="flex items-start justify-between">
          <div>
            <h3 class="text-xl font-bold text-ink">
              {if @editing_id, do: "Sửa gói", else: "Tạo gói mới"}
            </h3>
            <p class="text-sm text-ink-muted">Gói dịch vụ Gửi Index (ví riêng).</p>
          </div>
          <button
            type="button"
            phx-click="close"
            class="rounded-md p-1 text-ink-muted hover:bg-surface-hover"
          >
            <.icon name="hero-x-mark" class="size-5" />
          </button>
        </div>

        <.form for={@form} phx-submit="save" class="mt-5 space-y-1">
          <.input field={@form[:name]} label="Tên" placeholder="Gói Index cơ bản" required />
          <.input field={@form[:credits]} type="number" label="Số credit" min="0" required />
          <.input field={@form[:days]} type="number" label="Số ngày" min="0" required />
          <.input field={@form[:price]} label="Giá (tuỳ chọn)" placeholder="0" />
          <.input field={@form[:active]} type="checkbox" label="Đang bật" />
          <div class="mt-4 flex gap-3 border-t border-line pt-4">
            <.button variant="primary">{if @editing_id, do: "Cập nhật", else: "Tạo"}</.button>
            <.button type="button" variant="secondary" phx-click="close">Hủy</.button>
          </div>
        </.form>
      </div>
    </div>
    """
  end
end
