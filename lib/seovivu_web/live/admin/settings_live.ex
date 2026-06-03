defmodule SeovivuWeb.Admin.SettingsLive do
  @moduledoc """
  Admin Telegram bot settings: bot token/username (with a live Test that calls
  getMe) and webhook registration. ScrapingDog, proxies and concurrency live on
  their own admin pages.
  """
  use SeovivuWeb, :live_view

  alias Seovivu.{Settings, Telegram}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(:page_title, "Bot Telegram") |> load()}
  end

  defp load(socket) do
    telegram_form =
      to_form(
        %{
          "bot_token" => Settings.get_value("telegram.bot_token", ""),
          "bot_username" => Settings.get_value("telegram.bot_username", "")
        },
        as: :telegram
      )

    socket
    |> assign(:telegram_form, telegram_form)
    |> assign(
      :webhook_form,
      to_form(%{"base_url" => Telegram.webhook_base_url() || SeovivuWeb.Endpoint.url()},
        as: :webhook
      )
    )
    |> assign(:bot_username, Settings.get_value("telegram.bot_username", ""))
    |> assign(:webhook_active, Telegram.webhook_active?())
    |> assign(:templates, Map.new(Telegram.template_keys(), &{&1, Telegram.get_template(&1)}))
    |> assign(:broadcast_form, to_form(%{"text" => ""}, as: :broadcast))
  end

  @impl true
  def handle_event("submit_telegram", %{"intent" => "test", "telegram" => params}, socket) do
    # Keep what the admin typed in the inputs.
    socket = assign(socket, :telegram_form, to_form(params, as: :telegram))

    case Telegram.test_connection(params["bot_token"]) do
      {:ok, %{"username" => username}} ->
        {:noreply, socket |> put_flash(:info, "Đã kết nối tới @#{username}.")}

      {:ok, _me} ->
        {:noreply, put_flash(socket, :info, "Đã kết nối tới Telegram.")}

      {:error, :not_configured} ->
        {:noreply, put_flash(socket, :error, "Hãy nhập bot token trước.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Lỗi Telegram: #{inspect(reason)}")}
    end
  end

  def handle_event("submit_telegram", %{"telegram" => params}, socket) do
    Settings.put_value("telegram.bot_token", params["bot_token"] || "")
    Settings.put_value("telegram.bot_username", params["bot_username"] || "")
    {:noreply, socket |> put_flash(:info, "Đã lưu cài đặt Telegram.") |> load()}
  end

  def handle_event("set_webhook", %{"webhook" => %{"base_url" => base_url}}, socket) do
    case Telegram.set_webhook(base_url) do
      {:ok, _} ->
        {:noreply,
         put_flash(socket, :info, "Đã đặt webhook tại #{base_url}/telegram/webhook/...")}

      {:error, :not_configured} ->
        {:noreply, put_flash(socket, :error, "Hãy lưu bot token trước.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Không đặt được webhook: #{inspect(reason)}")}
    end
  end

  def handle_event("save_templates", %{"templates" => params}, socket) do
    Enum.each(params, fn {key, value} -> Telegram.put_template(key, value) end)
    {:noreply, socket |> put_flash(:info, "Đã lưu mẫu tin nhắn.") |> load()}
  end

  def handle_event("broadcast", %{"broadcast" => %{"text" => text}}, socket) do
    case Telegram.broadcast(text) do
      {:ok, count} ->
        {:noreply,
         socket
         |> put_flash(:info, "Đang gửi thông báo tới #{count} người dùng.")
         |> assign(:broadcast_form, to_form(%{"text" => ""}, as: :broadcast))}

      {:error, :empty} ->
        {:noreply, put_flash(socket, :error, "Hãy nhập nội dung thông báo.")}
    end
  end

  def handle_event("delete_webhook", _params, socket) do
    case Telegram.delete_webhook() do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Đã xóa webhook. Dev sẽ nhận update qua long-polling.")
         |> load()}

      {:error, :not_configured} ->
        {:noreply, put_flash(socket, :error, "Hãy lưu bot token trước.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Không xóa được webhook: #{inspect(reason)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin
      current_user={@current_user}
      active={:settings}
      page_title="Bot Telegram"
      flash={@flash}
    >
      <div class="mb-6">
        <h2 class="text-3xl font-bold tracking-tight text-ink">Bot Telegram</h2>
        <p class="mt-1 text-ink-muted">Đăng ký người dùng và gửi mật khẩu, thông báo.</p>
      </div>

      <div class="grid gap-6 lg:grid-cols-2 lg:items-start">
        <div class="space-y-6">
          <section class="rounded-card border border-line bg-surface p-6 shadow-card">
            <div class="flex items-start justify-between gap-3">
              <h3 class="text-lg font-semibold text-ink">Thông tin bot</h3>
              <.badge :if={@bot_username not in [nil, ""]} tone="success">@{@bot_username}</.badge>
            </div>
            <.form for={@telegram_form} phx-submit="submit_telegram" class="mt-4 space-y-1">
              <.input
                field={@telegram_form[:bot_token]}
                label="Token bot"
                placeholder="123456:ABC-DEF..."
              />
              <.input
                field={@telegram_form[:bot_username]}
                label="Username bot"
                placeholder="seovivu_bot"
              />
              <div class="mt-3 flex gap-3">
                <.button name="intent" value="save">Lưu</.button>
                <.button name="intent" value="test" variant="secondary">Kiểm tra</.button>
              </div>
            </.form>

            <div class="mt-5 border-t border-line pt-4">
              <div class="flex items-center gap-2">
                <p class="text-sm font-semibold text-ink">Webhook (production)</p>
                <.badge :if={@webhook_active} tone="success">đang bật</.badge>
                <.badge :if={!@webhook_active} tone="neutral">tắt</.badge>
              </div>
              <p class="mt-1 text-xs text-ink-muted">
                Khi phát triển, cập nhật nhận qua long-polling nên phần này là tuỳ chọn. Bật webhook sẽ
                tạm dừng long-polling; xóa webhook để quay lại nhận qua long-polling.
              </p>
              <.form for={@webhook_form} phx-submit="set_webhook" class="mt-3 space-y-1">
                <.input
                  field={@webhook_form[:base_url]}
                  label="URL gốc công khai"
                  placeholder="https://seovivu.com"
                />
                <div class="mt-3 flex gap-3">
                  <.button type="submit">Đặt webhook</.button>
                  <.button type="button" variant="secondary" phx-click="delete_webhook">
                    Xóa webhook
                  </.button>
                </div>
              </.form>
            </div>
          </section>

          <section class="rounded-card border border-line bg-surface p-6 shadow-card">
            <h3 class="text-lg font-semibold text-ink">Gửi thông báo hàng loạt</h3>
            <p class="mt-1 text-xs text-ink-muted">
              Gửi một tin nhắn tới tất cả người dùng đang hoạt động qua bot.
            </p>
            <.form for={@broadcast_form} phx-submit="broadcast" class="mt-4 space-y-1">
              <.input
                field={@broadcast_form[:text]}
                type="textarea"
                rows="4"
                placeholder="Nội dung thông báo gửi tới mọi người dùng..."
              />
              <.button type="submit" class="mt-2">
                <.icon name="hero-paper-airplane" class="size-4" /> Gửi cho tất cả
              </.button>
            </.form>
          </section>
        </div>

        <section class="rounded-card border border-line bg-surface p-6 shadow-card">
          <h3 class="text-lg font-semibold text-ink">Mẫu tin nhắn</h3>
          <p class="mt-1 text-xs text-ink-muted">
            Tuỳ chỉnh nội dung bot gửi. Dùng placeholder
            <code class="rounded bg-page px-1">{"{{username}}"}</code>
            và <code class="rounded bg-page px-1">{"{{password}}"}</code>
            để chèn dữ liệu.
          </p>
          <form phx-submit="save_templates" class="mt-4 space-y-4">
            <div :for={key <- Telegram.template_keys()}>
              <label class="mb-1 block text-sm font-medium text-ink-secondary">
                {template_label(key)}
              </label>
              <textarea
                name={"templates[#{key}]"}
                rows="5"
                class="block w-full rounded-button border border-line bg-surface px-3 py-2 text-sm text-ink shadow-soft focus:border-accent focus:outline-none focus:ring-2 focus:ring-accent/30"
              >{@templates[key]}</textarea>
            </div>
            <.button type="submit">Lưu mẫu tin nhắn</.button>
          </form>
        </section>
      </div>
    </Layouts.admin>
    """
  end

  defp template_label("welcome"), do: "Tin chào mừng (đăng ký mới)"
  defp template_label("already_registered"), do: "Tin khi đã đăng ký"
  defp template_label("reset"), do: "Tin đặt lại mật khẩu"
  defp template_label(other), do: to_string(other)
end
