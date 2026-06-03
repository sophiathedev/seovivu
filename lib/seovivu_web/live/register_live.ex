defmodule SeovivuWeb.RegisterLive do
  @moduledoc """
  Registration via Telegram. Shows a deep link to the bot and waits for the user
  to press Start; when the bot links the account it pushes the result here over
  PubSub and we reveal the "go to login" step.
  """
  use SeovivuWeb, :live_view

  alias Seovivu.Telegram

  @impl true
  def mount(_params, _session, socket) do
    nonce = :crypto.strong_rand_bytes(12) |> Base.url_encode64(padding: false)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Seovivu.PubSub, "register:#{nonce}")
    end

    link =
      case Telegram.deep_link(nonce) do
        {:ok, url} -> url
        :error -> nil
      end

    {:ok,
     socket
     |> assign(:page_title, "Đăng ký")
     |> assign(:nonce, nonce)
     |> assign(:link, link)
     |> assign(:configured, Telegram.configured?() and not is_nil(link))
     |> assign(:linked, false)
     |> assign(:linked_username, nil), layout: false}
  end

  @impl true
  def handle_info({:telegram_linked, %{username: username}}, socket) do
    {:noreply, socket |> assign(:linked, true) |> assign(:linked_username, username)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex min-h-[100dvh] items-center justify-center bg-page px-4">
      <div class="w-full max-w-md">
        <div class="mb-8 flex items-center justify-center gap-3">
          <span class="flex size-11 items-center justify-center rounded-md bg-brand text-lg font-bold text-white">
            S
          </span>
          <div>
            <div class="text-xl font-bold leading-none text-ink">SEO</div>
            <div class="text-xs text-ink-muted">Bộ công cụ SEO</div>
          </div>
        </div>

        <div class="rounded-card border border-line bg-surface p-8 shadow-card">
          <h1 class="text-2xl font-bold tracking-tight text-ink">Đăng ký bằng Telegram</h1>
          <p class="mt-2 text-sm text-ink-secondary">
            Tài khoản của bạn được tạo qua bot Telegram, bot sẽ gửi mật khẩu để bạn đăng nhập.
          </p>

          <div :if={@linked} class="mt-6">
            <div class="flex items-center gap-3 rounded-button border border-success-border bg-success-bg px-4 py-3 text-sm text-success">
              <.icon name="hero-check-circle" class="size-5 shrink-0" />
              <span>
                Đã liên kết với <span class="font-semibold">{@linked_username}</span>. Kiểm tra Telegram để lấy mật khẩu.
              </span>
            </div>
            <.button navigate={~p"/login"} variant="primary" class="mt-4 w-full">
              Tiếp tục đăng nhập
            </.button>
          </div>

          <div :if={not @linked and @configured} class="mt-6">
            <ol class="space-y-3 text-sm text-ink-secondary">
              <li class="flex gap-3">
                <span class="flex size-6 shrink-0 items-center justify-center rounded-full bg-brand-soft text-xs font-bold text-ink">
                  1
                </span>
                Mở bot và bấm Start.
              </li>
              <li class="flex gap-3">
                <span class="flex size-6 shrink-0 items-center justify-center rounded-full bg-brand-soft text-xs font-bold text-ink">
                  2
                </span>
                Bot tạo tài khoản và gửi mật khẩu cho bạn.
              </li>
              <li class="flex gap-3">
                <span class="flex size-6 shrink-0 items-center justify-center rounded-full bg-brand-soft text-xs font-bold text-ink">
                  3
                </span>
                Trang này tự chuyển tiếp ngay khi bạn được liên kết.
              </li>
            </ol>

            <.button href={@link} target="_blank" variant="primary" class="mt-6 w-full">
              <.icon name="hero-paper-airplane" class="size-4" /> Mở bot Telegram
            </.button>

            <p class="mt-4 flex items-center justify-center gap-2 text-sm text-ink-muted">
              <.icon name="hero-arrow-path" class="size-4 motion-safe:animate-spin" />
              Đang chờ bạn bấm Start...
            </p>
          </div>

          <div
            :if={not @linked and not @configured}
            class="mt-6 rounded-button border border-line bg-page px-3 py-3 text-sm text-ink-muted"
          >
            Bot Telegram chưa được cấu hình. Vui lòng nhờ admin nhập bot token trong phần Cài đặt,
            rồi tải lại trang này.
          </div>
        </div>

        <p class="mt-6 text-center text-sm text-ink-muted">
          Đã có mật khẩu?
          <.link navigate={~p"/login"} class="font-semibold text-accent hover:underline">
            Đăng nhập
          </.link>
        </p>
      </div>
    </div>
    """
  end
end
