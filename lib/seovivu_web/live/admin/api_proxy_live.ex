defmodule SeovivuWeb.Admin.ApiProxyLive do
  @moduledoc """
  Admin page: the ScrapingDog API key (used directly by the Index Checker) and
  the proxy inventory (used by the proxied check tools). Both support live tests.
  """
  use SeovivuWeb, :live_view

  alias Seovivu.{Settings, Net}
  alias Seovivu.Net.Proxy

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(:page_title, "API & Proxy") |> load()}
  end

  defp load(socket) do
    socket
    |> assign(
      :scrapingdog_form,
      to_form(%{"api_key" => Settings.get_value("scrapingdog.api_key", "")}, as: :scrapingdog)
    )
    |> assign(:proxies, Net.list_proxies())
    |> assign(:proxy_form, to_form(Net.change_proxy(%Proxy{})))
  end

  @impl true
  def handle_event("submit_scrapingdog", %{"intent" => "test", "scrapingdog" => params}, socket) do
    # Test the typed key directly (keep the input as-is).
    socket = assign(socket, :scrapingdog_form, to_form(params, as: :scrapingdog))

    case Net.test_scrapingdog(params["api_key"] || "") do
      :ok ->
        {:noreply, put_flash(socket, :info, "ScrapingDog key hoạt động.")}

      {:error, :no_key} ->
        {:noreply, put_flash(socket, :error, "Hãy nhập API key trước.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Kiểm tra ScrapingDog thất bại: #{inspect(reason)}")}
    end
  end

  def handle_event("submit_scrapingdog", %{"scrapingdog" => params}, socket) do
    Settings.put_value("scrapingdog.api_key", params["api_key"] || "")
    {:noreply, socket |> put_flash(:info, "Đã lưu ScrapingDog API key.") |> load()}
  end

  def handle_event("submit_proxy", %{"intent" => "test", "proxy" => params}, socket) do
    # Test the typed proxy without adding it (keep the inputs).
    socket = assign(socket, :proxy_form, to_form(Net.change_proxy(%Proxy{}, params)))

    case Net.test_proxy_attrs(params) do
      {:ok, latency} ->
        {:noreply, put_flash(socket, :info, "Proxy hoạt động (#{latency} ms).")}

      {:error, :invalid} ->
        {:noreply, put_flash(socket, :error, "Nhập Host và Port hợp lệ trước.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Proxy không hoạt động: #{inspect(reason)}")}
    end
  end

  def handle_event("submit_proxy", %{"proxy" => params}, socket) do
    case Net.create_proxy(params) do
      {:ok, _} -> {:noreply, socket |> put_flash(:info, "Đã thêm proxy.") |> load()}
      {:error, changeset} -> {:noreply, assign(socket, :proxy_form, to_form(changeset))}
    end
  end

  def handle_event("import_proxies", %{"import" => %{"text" => text}}, socket) do
    {count, errors} = Net.import_proxies(text)

    msg =
      "Đã nhập #{count} proxy." <>
        if(errors == [], do: "", else: " Bỏ qua #{length(errors)} dòng.")

    {:noreply, socket |> put_flash(:info, msg) |> load()}
  end

  def handle_event("delete_proxy", %{"id" => id}, socket) do
    id |> Net.get_proxy!() |> Net.delete_proxy()
    {:noreply, socket |> put_flash(:info, "Đã xóa proxy.") |> load()}
  end

  def handle_event("test_proxy", %{"id" => id}, socket) do
    id |> Net.get_proxy!() |> Net.test_proxy()
    {:noreply, socket |> put_flash(:info, "Đã kiểm tra proxy.") |> load()}
  end

  def handle_event("test_all", _params, socket) do
    {ok, failed} = Net.test_all_proxies()

    {:noreply,
     socket |> put_flash(:info, "Đã kiểm tra tất cả proxy: #{ok} ok, #{failed} lỗi.") |> load()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin
      current_user={@current_user}
      active={:api_proxy}
      page_title="API & Proxy"
      flash={@flash}
    >
      <div class="mb-6">
        <h2 class="text-3xl font-bold tracking-tight text-ink">API & Proxy</h2>
        <p class="mt-1 text-ink-muted">Thông tin API ngoài và danh sách proxy đầu ra.</p>
      </div>

      <section class="mb-6 max-w-xl rounded-card border border-line bg-surface p-6 shadow-card">
        <h3 class="text-lg font-semibold text-ink">ScrapingDog API</h3>
        <p class="mt-1 text-sm text-ink-muted">
          Phục vụ Kiểm tra Index. Gọi API trực tiếp (không qua proxy).
        </p>
        <.form for={@scrapingdog_form} phx-submit="submit_scrapingdog" class="mt-4 space-y-1">
          <.input
            field={@scrapingdog_form[:api_key]}
            label="API key"
            placeholder="ScrapingDog key của bạn"
          />
          <div class="mt-3 flex gap-3">
            <.button name="intent" value="save">Lưu</.button>
            <.button name="intent" value="test" variant="secondary">Kiểm tra</.button>
          </div>
        </.form>
      </section>

      <section class="rounded-card border border-line bg-surface p-6 shadow-card">
        <div class="flex items-center justify-between">
          <div>
            <h3 class="text-lg font-semibold text-ink">Proxy</h3>
            <p class="mt-1 text-sm text-ink-muted">
              Dùng cho Trạng thái URL, Backlink và Redirect 301 để ẩn IP gốc.
            </p>
          </div>
          <.button type="button" variant="secondary" phx-click="test_all">Kiểm tra tất cả</.button>
        </div>

        <div class="mt-4 grid grid-cols-1 gap-4 lg:grid-cols-2">
          <.form for={@proxy_form} phx-submit="submit_proxy" class="space-y-1">
            <div class="grid grid-cols-2 gap-3">
              <.input field={@proxy_form[:host]} label="Host" placeholder="1.2.3.4" />
              <.input field={@proxy_form[:port]} type="number" label="Port" placeholder="8080" />
              <.input field={@proxy_form[:username]} label="Username (tuỳ chọn)" />
              <.input field={@proxy_form[:password]} label="Password (tuỳ chọn)" />
            </div>
            <div class="mt-3 flex gap-3">
              <.button name="intent" value="add">Thêm proxy</.button>
              <.button name="intent" value="test" variant="secondary">Kiểm tra</.button>
            </div>
          </.form>

          <.form for={to_form(%{}, as: :import)} phx-submit="import_proxies" class="space-y-1">
            <.input
              type="textarea"
              name="import[text]"
              value=""
              label="Nhập hàng loạt"
              placeholder="host:port hoặc host:port:user:pass (mỗi dòng một proxy)"
              rows="5"
            />
            <.button class="mt-3">Nhập danh sách</.button>
          </.form>
        </div>

        <div class="mt-6">
          <.table :if={@proxies != []} id="proxies" rows={@proxies}>
            <:col :let={p} label="Giao thức">{p.protocol}</:col>
            <:col :let={p} label="Host">{p.host}:{p.port}</:col>
            <:col :let={p} label="Trạng thái">
              <.badge tone={proxy_tone(p.status)}>{proxy_status(p.status)}</.badge>
            </:col>
            <:col :let={p} label="Độ trễ">
              {if p.last_latency_ms, do: "#{p.last_latency_ms} ms", else: "-"}
            </:col>
            <:col :let={p} label="Bật">{if p.active, do: "Có", else: "Không"}</:col>
            <:action :let={p}>
              <.link phx-click="test_proxy" phx-value-id={p.id} class="text-accent hover:underline">
                Kiểm tra
              </.link>
            </:action>
            <:action :let={p}>
              <.link
                phx-click="delete_proxy"
                phx-value-id={p.id}
                data-confirm="Xóa proxy này?"
                class="text-danger hover:underline"
              >
                Xóa
              </.link>
            </:action>
          </.table>
          <p
            :if={@proxies == []}
            class="rounded-button border border-line bg-page px-3 py-6 text-center text-sm text-ink-muted"
          >
            Chưa có proxy. Thêm ở trên hoặc nhập danh sách.
          </p>
        </div>
      </section>
    </Layouts.admin>
    """
  end

  defp proxy_tone(:ok), do: "success"
  defp proxy_tone(:failed), do: "danger"
  defp proxy_tone(_), do: "neutral"

  defp proxy_status(:ok), do: "Hoạt động"
  defp proxy_status(:failed), do: "Lỗi"
  defp proxy_status(_), do: "Chưa kiểm tra"
end
