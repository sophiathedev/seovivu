defmodule SeovivuWeb.Admin.ConcurrencyLive do
  @moduledoc "Admin page: per-feature maximum concurrent requests per user."
  use SeovivuWeb, :live_view

  alias Seovivu.Settings

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(:page_title, "Đa luồng") |> load()}
  end

  defp load(socket) do
    concurrency = Settings.list_feature_concurrency()

    form =
      concurrency
      |> Map.new(fn fc -> {Atom.to_string(fc.feature), fc.per_user_limit} end)
      |> to_form(as: :limits)

    socket |> assign(:concurrency, concurrency) |> assign(:form, form)
  end

  @impl true
  def handle_event("save", %{"limits" => limits}, socket) do
    for fc <- socket.assigns.concurrency do
      case limits[Atom.to_string(fc.feature)] do
        nil -> :ok
        value -> Settings.update_feature_concurrency(fc, %{per_user_limit: value})
      end
    end

    {:noreply, socket |> put_flash(:info, "Đã lưu giới hạn đa luồng.") |> load()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin
      current_user={@current_user}
      active={:concurrency}
      page_title="Đa luồng"
      flash={@flash}
    >
      <div class="mb-6">
        <h2 class="text-3xl font-bold tracking-tight text-ink">Đa luồng</h2>
        <p class="mt-1 text-ink-muted">
          Số request tối đa một người dùng chạy đồng thời cho mỗi tính năng. Giá trị cao hơn giúp xử lý nhanh hơn nhưng tăng tải lên proxy và API.
        </p>
      </div>

      <section class="max-w-2xl rounded-card border border-line bg-surface p-6 shadow-card">
        <.form for={@form} phx-submit="save" class="space-y-4">
          <div
            :for={fc <- @concurrency}
            class="flex items-center justify-between gap-4 border-b border-line-soft pb-4 last:border-0"
          >
            <div>
              <p class="font-semibold text-ink">{feature_label(fc.feature)}</p>
              <p class="text-xs text-ink-muted">{feature_hint(fc.feature)}</p>
            </div>
            <div class="w-28">
              <.input type="number" field={@form[fc.feature]} min="1" max="100" />
            </div>
          </div>
          <.button variant="primary">Lưu giới hạn</.button>
        </.form>
      </section>
    </Layouts.admin>
    """
  end

  defp feature_label(:check_index), do: "Kiểm tra Index"
  defp feature_label(:submit_index), do: "Gửi Index"
  defp feature_label(:url_status), do: "Trạng thái URL"
  defp feature_label(:backlink), do: "Backlink"
  defp feature_label(:redirect_301), do: "Redirect 301"
  defp feature_label(other), do: to_string(other)

  defp feature_hint(:check_index), do: "Gọi trực tiếp API ScrapingDog."
  defp feature_hint(:submit_index), do: "Tác vụ gửi index trên subdomain."
  defp feature_hint(_), do: "Định tuyến qua proxy."
end
