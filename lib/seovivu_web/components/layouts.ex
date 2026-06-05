defmodule SeovivuWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use SeovivuWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div
      id={@id}
      aria-live="polite"
      class="fixed top-4 right-4 z-50 flex w-80 flex-col gap-2 sm:w-96"
    >
      <.flash kind={:info} flash={@flash} autohide />
      <.flash kind={:error} flash={@flash} autohide />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("Mất kết nối internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Đang thử kết nối lại")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Đã có lỗi xảy ra!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Đang thử kết nối lại")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  The authenticated user dashboard shell: fixed left sidebar + top bar + content.
  """
  attr :current_user, :map, required: true
  attr :active, :atom, default: nil
  attr :page_title, :string, default: nil
  attr :credits, :any, default: nil
  attr :days, :any, default: nil
  attr :flash, :map, default: %{}
  slot :inner_block, required: true

  def dashboard(assigns) do
    assigns = assign(assigns, nav: user_nav(), brand_subtitle: "Bộ công cụ SEO", mode: :user)
    app_shell(assigns)
  end

  @doc "The admin dashboard shell (same chrome, admin navigation)."
  attr :current_user, :map, required: true
  attr :active, :atom, default: nil
  attr :page_title, :string, default: nil
  attr :credits, :any, default: nil
  attr :days, :any, default: nil
  attr :flash, :map, default: %{}
  slot :inner_block, required: true

  def admin(assigns) do
    assigns = assign(assigns, nav: admin_nav(), brand_subtitle: "Quản trị", mode: :admin)
    app_shell(assigns)
  end

  @doc "Slim top-bar shell for the index.seovivu.com (Submit Index) subdomain."
  attr :current_user, :map, required: true
  attr :page_title, :string, default: nil
  attr :credits, :any, default: nil
  slot :inner_block, required: true
  attr :flash, :map, default: %{}

  def index(assigns) do
    ~H"""
    <div class="min-h-[100dvh] bg-page">
      <header class="border-b border-line bg-surface">
        <div class="mx-auto flex max-w-5xl items-center justify-between gap-4 px-6 py-4">
          <.link navigate={~p"/"} class="flex items-center gap-3">
            <span class="flex size-10 items-center justify-center rounded-md bg-brand text-lg font-bold text-white">
              S
            </span>
            <div>
              <div class="text-lg font-bold leading-none text-ink">Gửi Index</div>
              <div class="text-xs text-ink-muted">index.seovivu.com</div>
            </div>
          </.link>
          <div class="flex items-center gap-4 text-sm">
            <span
              :if={@credits != nil}
              class="inline-flex items-center gap-1.5 rounded-button border border-line bg-page px-3 py-1.5 font-semibold text-ink"
            >
              <.icon name="hero-bolt" class="size-4 text-accent" /> {@credits} credit
            </span>
            <.link
              href={SeovivuWeb.Endpoint.url()}
              class="inline-flex items-center gap-1.5 rounded-button border border-line bg-page px-3 py-1.5 font-semibold text-ink hover:bg-surface-hover"
              title="Về trang chủ Seovivu"
            >
              <.icon name="hero-home" class="size-4" />
              <span class="hidden sm:inline">Trang chủ</span>
            </.link>
            <.link
              href={~p"/logout"}
              method="delete"
              class="rounded-md p-2 text-ink-muted hover:bg-surface-hover hover:text-ink"
              title="Đăng xuất"
            >
              <.icon name="hero-arrow-right-on-rectangle" class="size-5" />
            </.link>
          </div>
        </div>
      </header>

      <main class="mx-auto max-w-5xl px-6 py-8">{render_slot(@inner_block)}</main>

      <.flash_group flash={@flash} />
    </div>
    """
  end

  # Shared sidebar + topbar chrome used by both dashboard/1 and admin/1.
  defp app_shell(assigns) do
    ~H"""
    <div class="min-h-[100dvh] bg-page">
      <aside class="fixed inset-y-0 left-0 z-20 flex w-[272px] flex-col border-r border-line bg-surface">
        <div class="flex items-center gap-3 px-5 py-5">
          <span class="flex size-10 items-center justify-center rounded-md bg-brand text-lg font-bold text-white">
            S
          </span>
          <div>
            <div class="text-lg font-bold leading-none text-ink">SEO</div>
            <div class="text-xs text-ink-muted">{@brand_subtitle}</div>
          </div>
        </div>

        <nav class="flex-1 space-y-6 overflow-y-auto px-3 py-2">
          <div :for={section <- @nav}>
            <p class="px-3 pb-2 text-[11px] font-bold uppercase tracking-wider text-ink-light">
              {section.group}
            </p>
            <ul class="space-y-1">
              <li :for={item <- section.items}>
                <.nav_item item={item} active={@active} />
              </li>
            </ul>
          </div>
        </nav>

        <div class="space-y-3 border-t border-line p-3">
          <.link
            :if={@current_user.role == :admin}
            navigate={if @mode == :admin, do: ~p"/app", else: ~p"/admin"}
            class="flex items-center gap-3 rounded-button bg-gray-200 px-3 py-2.5 text-sm font-medium text-gray-700 hover:bg-gray-300"
          >
            <.icon
              name={if @mode == :admin, do: "hero-squares-2x2", else: "hero-wrench-screwdriver"}
              class="size-5"
            />
            <span class="flex-1">
              {if @mode == :admin, do: "Khu vực người dùng", else: "Khu vực quản trị"}
            </span>
            <.icon name="hero-arrow-right" class="size-4" />
          </.link>

          <div class="flex items-center gap-3 rounded-card border border-line p-3">
            <span class="flex size-10 items-center justify-center rounded-full bg-page font-bold text-ink">
              {user_initial(@current_user)}
            </span>
            <div class="min-w-0 flex-1">
              <div class="truncate text-sm font-bold text-ink">
                {@current_user.username || @current_user.telegram_first_name || "Người dùng"}
              </div>
              <div class="text-xs font-semibold uppercase tracking-wide text-ink-muted">
                {role_label(@current_user.role)}
              </div>
            </div>
            <.link
              href={~p"/logout"}
              method="delete"
              class="rounded-md p-2 text-ink-muted hover:bg-surface-hover hover:text-ink"
              title="Đăng xuất"
            >
              <.icon name="hero-arrow-right-on-rectangle" class="size-5" />
            </.link>
          </div>
        </div>
      </aside>

      <div class="pl-[272px]">
        <header class="flex items-center justify-between gap-4 border-b border-line bg-surface px-8 py-4">
          <h1 class="text-lg font-semibold text-ink">{@page_title}</h1>
          <div :if={@credits} class="flex items-center gap-3 text-sm">
            <span class="inline-flex items-center gap-1.5 rounded-button border border-line bg-page px-3 py-1.5 font-semibold text-ink">
              <.icon name="hero-bolt" class="size-4 text-accent" /> {@credits} credit
            </span>
            <span :if={@days} class="text-ink-muted">còn {@days} ngày</span>
          </div>
        </header>

        <main class="px-8 py-7">
          {render_slot(@inner_block)}
        </main>
      </div>

      <.flash_group flash={@flash} />
    </div>
    """
  end

  attr :item, :map, required: true
  attr :active, :atom, default: nil

  defp nav_item(%{item: %{enabled: false}} = assigns) do
    ~H"""
    <span
      class="flex cursor-not-allowed items-center gap-3 rounded-button px-3 py-2.5 text-sm font-medium text-ink-light"
      title="Sắp ra mắt"
    >
      <.icon name={@item.icon} class="size-5" />
      <span class="flex-1">{@item.label}</span>
      <span class="rounded-badge bg-page px-2 py-0.5 text-[10px] font-semibold uppercase text-ink-light">
        sắp ra
      </span>
    </span>
    """
  end

  defp nav_item(assigns) do
    ~H"""
    <.link
      href={@item.href}
      class={[
        "flex items-center gap-3 rounded-button px-3 py-2.5 text-sm transition-colors",
        if(@item.key == @active,
          do: "bg-brand-soft font-semibold text-ink",
          else: "font-medium text-ink-secondary hover:bg-surface-hover hover:text-ink"
        )
      ]}
    >
      <.icon name={@item.icon} class="size-5" />
      <span class="flex-1">{@item.label}</span>
    </.link>
    """
  end

  defp user_initial(user) do
    (user.username || user.telegram_first_name || "U")
    |> String.first()
    |> Kernel.||("U")
    |> String.upcase()
  end

  defp role_label(:admin), do: "Quản trị"
  defp role_label(_), do: "Thành viên"

  defp user_nav do
    [
      %{
        group: "Danh mục",
        items: [
          %{
            key: :overview,
            label: "Bảng điều khiển",
            icon: "hero-home",
            href: "/app",
            enabled: true
          },
          %{
            key: :check_index,
            label: "Kiểm tra Index",
            icon: "hero-magnifying-glass",
            href: "/app/check-index",
            enabled: true
          },
          %{
            key: :submit_index,
            label: "Gửi Index",
            icon: "hero-paper-airplane",
            href: "/go/index",
            enabled: true
          },
          %{
            key: :url_status,
            label: "Kiểm tra trạng thái URL",
            icon: "hero-link",
            href: "/app/url-status",
            enabled: true
          },
          %{
            key: :backlink,
            label: "Kiểm tra Backlink",
            icon: "hero-arrow-trending-up",
            href: "/app/backlink",
            enabled: true
          },
          %{
            key: :redirect,
            label: "Trạng thái Redirect 301",
            icon: "hero-arrows-right-left",
            href: "/app/redirect",
            enabled: true
          },
          %{
            key: :disavow,
            label: "Disavow Link",
            icon: "hero-shield-exclamation",
            href: "/app/disavow",
            enabled: true
          },
          %{
            key: :robots,
            label: "Tạo Robots.txt",
            icon: "hero-document-text",
            href: "/app/robots",
            enabled: true
          }
        ]
      },
      %{
        group: "Tài khoản",
        items: [
          %{
            key: :history,
            label: "Lịch sử",
            icon: "hero-clock",
            href: "/app/history",
            enabled: true
          },
          %{
            key: :upgrade,
            label: "Nâng cấp tài khoản",
            icon: "hero-bolt",
            href: "#",
            enabled: false
          },
          %{
            key: :contact,
            label: "Liên hệ admin",
            icon: "hero-chat-bubble-left-right",
            href: "#",
            enabled: false
          }
        ]
      }
    ]
  end

  defp admin_nav do
    [
      %{
        group: "Quản trị",
        items: [
          %{
            key: :overview,
            label: "Tổng quan",
            icon: "hero-squares-2x2",
            href: "/admin",
            enabled: true
          },
          %{
            key: :users,
            label: "Quản lý người dùng",
            icon: "hero-users",
            href: "/admin/users",
            enabled: true
          },
          %{
            key: :quota,
            label: "Thiết lập gói",
            icon: "hero-rectangle-stack",
            href: "/admin/quota",
            enabled: true
          },
          %{
            key: :concurrency,
            label: "Đa luồng",
            icon: "hero-bars-3",
            href: "/admin/concurrency",
            enabled: true
          },
          %{
            key: :api_proxy,
            label: "API & Proxy",
            icon: "hero-globe-alt",
            href: "/admin/api-proxy",
            enabled: true
          },
          %{
            key: :settings,
            label: "Telegram bot",
            icon: "hero-paper-airplane",
            href: "/admin/settings",
            enabled: true
          }
        ]
      },
      %{
        group: "Gửi Index",
        items: [
          %{
            key: :index_projects,
            label: "Dự án Gửi Index",
            icon: "hero-rectangle-stack",
            href: "/admin/index/projects",
            enabled: true
          },
          %{
            key: :index_quota,
            label: "Gói Gửi Index",
            icon: "hero-rectangle-stack",
            href: "/admin/index/quota",
            enabled: true
          }
        ]
      }
    ]
  end
end
