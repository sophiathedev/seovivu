defmodule SeovivuWeb.Admin.UserManagerLive do
  @moduledoc """
  Admin user management: search, paginated list, and a per-user manage panel for
  credit adjustments, package upgrades, password resets, profile edits, banning
  and deletion.
  """
  use SeovivuWeb, :live_view

  alias Seovivu.{Accounts, Billing, Catalog, Telegram}

  @per_page 20

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Quản lý người dùng")
     |> assign(:search, "")
     |> assign(:offset, 0)
     |> assign(:per_page, @per_page)
     |> assign(:packages, Catalog.list_packages(:main))
     |> assign(:selected, nil)
     |> assign(:new_password, nil)
     |> assign_passwordless()
     |> load_users()}
  end

  defp assign_passwordless(socket),
    do: assign(socket, :passwordless_count, Accounts.count_users_without_password())

  defp load_users(socket) do
    opts = [search: socket.assigns.search, limit: @per_page, offset: socket.assigns.offset]

    socket
    |> assign(:users, Accounts.list_users(opts))
    |> assign(:total, Accounts.count_users(search: socket.assigns.search))
  end

  defp select(socket, user_id) do
    user = Accounts.get_user_with_wallets!(user_id)

    socket
    |> assign(:selected, user)
    |> assign(:new_password, nil)
    |> assign(:credit_form, to_form(%{"amount" => "100"}, as: :credit))
    |> assign(:profile_form, to_form(Accounts.change_user_admin(user), as: :user))
  end

  @impl true
  def handle_event("search", %{"q" => q}, socket) do
    {:noreply, socket |> assign(:search, q) |> assign(:offset, 0) |> load_users()}
  end

  def handle_event("page", %{"page" => page}, socket) do
    total_pages = max(1, div(socket.assigns.total + @per_page - 1, @per_page))

    case Integer.parse(page) do
      {n, _} ->
        n = n |> max(1) |> min(total_pages)
        {:noreply, socket |> assign(:offset, (n - 1) * @per_page) |> load_users()}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("issue_passwords", _params, socket) do
    cond do
      socket.assigns.passwordless_count == 0 ->
        {:noreply, socket}

      not Telegram.configured?() ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Chưa cấu hình bot Telegram nên không thể gửi mật khẩu. Vào Cài đặt để kết nối bot trước."
         )}

      true ->
        count = Telegram.issue_passwords_to_passwordless_users()

        {:noreply,
         socket
         |> put_flash(:info, "Đã cấp mật khẩu cho #{count} tài khoản và gửi qua Telegram.")
         |> assign_passwordless()
         |> load_users()}
    end
  end

  def handle_event("manage", %{"id" => id}, socket), do: {:noreply, select(socket, id)}
  def handle_event("close", _params, socket), do: {:noreply, assign(socket, :selected, nil)}

  def handle_event("adjust_credit", %{"amount" => amount, "op" => op}, socket) do
    user = socket.assigns.selected
    wallet = Billing.get_wallet(user.id, :main)

    case Integer.parse(amount) do
      {n, _} when n > 0 ->
        delta = if op == "subtract", do: -n, else: n
        Billing.admin_adjust(wallet, delta, %{"by" => socket.assigns.current_user.username})
        {:noreply, socket |> put_flash(:info, "Đã cập nhật credit.") |> refresh(user.id)}

      _ ->
        {:noreply, put_flash(socket, :error, "Nhập một số dương.")}
    end
  end

  def handle_event("adjust_index_credit", %{"amount" => amount, "op" => op}, socket) do
    user = socket.assigns.selected
    wallet = Billing.get_wallet(user.id, :index)

    case Integer.parse(amount) do
      {n, _} when n > 0 ->
        delta = if op == "subtract", do: -n, else: n
        Billing.admin_adjust(wallet, delta, %{"by" => socket.assigns.current_user.username})
        {:noreply, socket |> put_flash(:info, "Đã cập nhật credit Index.") |> refresh(user.id)}

      _ ->
        {:noreply, put_flash(socket, :error, "Nhập một số dương.")}
    end
  end

  def handle_event("set_days", %{"days" => days}, socket) do
    user = socket.assigns.selected
    wallet = Billing.get_wallet(user.id, :main)

    case Integer.parse(days) do
      {n, _} when n >= 0 ->
        Billing.set_days_remaining(wallet, n)
        {:noreply, socket |> put_flash(:info, "Đã đặt số ngày còn lại.") |> refresh(user.id)}

      _ ->
        {:noreply, put_flash(socket, :error, "Nhập một số ngày không âm.")}
    end
  end

  def handle_event("apply_package", %{"package_id" => ""}, socket), do: {:noreply, socket}

  def handle_event("apply_package", %{"package_id" => id}, socket) do
    user = socket.assigns.selected
    package = Catalog.get_package!(id)
    Billing.apply_package(Billing.get_wallet(user.id, :main), package)
    {:noreply, socket |> put_flash(:info, "Đã áp dụng gói #{package.name}.") |> refresh(user.id)}
  end

  def handle_event("reset_password", _params, socket) do
    user = socket.assigns.selected

    case Accounts.reset_password(user) do
      {:ok, _user, password} ->
        if Telegram.configured?(),
          do:
            Telegram.send_message_async(
              user.telegram_id,
              "Mật khẩu của bạn đã được admin đặt lại:\n\n#{password}"
            )

        {:noreply,
         socket |> assign(:new_password, password) |> put_flash(:info, "Đã đặt lại mật khẩu.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Không đặt lại được mật khẩu.")}
    end
  end

  def handle_event("save_profile", %{"user" => params}, socket) do
    case Accounts.update_user_admin(socket.assigns.selected, params) do
      {:ok, user} ->
        {:noreply, socket |> put_flash(:info, "Đã cập nhật hồ sơ.") |> refresh(user.id)}

      {:error, changeset} ->
        {:noreply, assign(socket, :profile_form, to_form(changeset, as: :user))}
    end
  end

  def handle_event("ban", _params, socket) do
    {:ok, user} = Accounts.ban_user(socket.assigns.selected)
    {:noreply, socket |> put_flash(:info, "Đã khóa người dùng.") |> refresh(user.id)}
  end

  def handle_event("unban", _params, socket) do
    {:ok, user} = Accounts.unban_user(socket.assigns.selected)
    {:noreply, socket |> put_flash(:info, "Đã mở khóa người dùng.") |> refresh(user.id)}
  end

  def handle_event("delete", _params, socket) do
    Accounts.delete_user(socket.assigns.selected)

    {:noreply,
     socket |> assign(:selected, nil) |> put_flash(:info, "Đã xóa người dùng.") |> load_users()}
  end

  defp refresh(socket, user_id), do: socket |> load_users() |> select(user_id)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin
      current_user={@current_user}
      active={:users}
      page_title="Quản lý người dùng"
      flash={@flash}
    >
      <div class="mb-6 flex flex-wrap items-end justify-between gap-4">
        <div>
          <h2 class="text-3xl font-bold tracking-tight text-ink">Quản lý người dùng</h2>
          <p class="mt-1 text-ink-muted">{@total} người dùng.</p>
        </div>
        <form phx-change="search" phx-submit="search" class="w-72">
          <input
            name="q"
            value={@search}
            placeholder="Tìm theo username hoặc Telegram ID"
            class="block w-full rounded-button border border-line bg-surface px-3 py-2 text-sm text-ink shadow-soft placeholder:text-ink-light focus:border-accent focus:outline-none focus:ring-2 focus:ring-accent/30"
          />
        </form>
      </div>

      <div
        :if={@passwordless_count > 0}
        class="mb-6 flex flex-wrap items-center justify-between gap-4 rounded-card border border-warning bg-warning-bg px-5 py-4 shadow-soft"
      >
        <div class="flex items-start gap-3">
          <.icon name="hero-key" class="mt-0.5 size-5 shrink-0 text-warning" />
          <div>
            <p class="font-semibold text-warning">
              {@passwordless_count} tài khoản chưa có mật khẩu
            </p>
            <p class="mt-0.5 text-sm text-ink-muted">
              Đây là các tài khoản nhập từ hệ thống cũ. Cấp mật khẩu mới và gửi cho từng người qua Telegram.
            </p>
          </div>
        </div>
        <.button
          type="button"
          phx-click="issue_passwords"
          data-confirm={"Cấp mật khẩu mới và gửi qua Telegram cho #{@passwordless_count} tài khoản?"}
        >
          Cấp & gửi qua Telegram
        </.button>
      </div>

      <.table :if={@users != []} id="users" rows={@users}>
        <:col :let={u} label="ID">{u.id}</:col>
        <:col :let={u} label="Người dùng">
          <div class="font-semibold text-ink">{u.username || u.telegram_first_name || "-"}</div>
          <div class="text-xs text-ink-muted">tg:{u.telegram_id}</div>
        </:col>
        <:col :let={u} label="Hạng">{tier(u)}</:col>
        <:col :let={u} label="Credit">{credits(u)}</:col>
        <:col :let={u} label="Số ngày">{days(u)}</:col>
        <:col :let={u} label="Trạng thái">
          <.badge tone={if u.status == :active, do: "success", else: "danger"}>
            {status_label(u.status)}
          </.badge>
        </:col>
        <:col :let={u} label="Ngày tạo">{date(u.inserted_at)}</:col>
        <:action :let={u}>
          <.link
            phx-click="manage"
            phx-value-id={u.id}
            class="font-semibold text-accent hover:underline"
          >
            Quản lý
          </.link>
        </:action>
      </.table>

      <p
        :if={@users == []}
        class="rounded-card border border-line bg-surface px-3 py-10 text-center text-sm text-ink-muted shadow-soft"
      >
        Không có người dùng phù hợp.
      </p>

      <div
        :if={@total > 0}
        class="mt-4 flex flex-wrap items-center justify-between gap-3 text-sm text-ink-muted"
      >
        <span>Hiển thị {@offset + 1}-{min(@offset + @per_page, @total)} / {@total}</span>
        <.pagination
          page={div(@offset, @per_page) + 1}
          total={@total}
          per_page={@per_page}
          event="page"
        />
      </div>

      <.manage_panel
        :if={@selected}
        user={@selected}
        packages={@packages}
        credit_form={@credit_form}
        profile_form={@profile_form}
        new_password={@new_password}
      />
    </Layouts.admin>
    """
  end

  attr :user, :map, required: true
  attr :packages, :list, required: true
  attr :credit_form, :map, required: true
  attr :profile_form, :map, required: true
  attr :new_password, :any, required: true

  defp manage_panel(assigns) do
    ~H"""
    <div class="fixed inset-0 z-40 flex justify-end bg-ink/30">
      <div
        class="h-full w-full max-w-md overflow-y-auto bg-surface p-6 shadow-card"
        phx-click-away="close"
      >
        <div class="flex items-start justify-between">
          <div>
            <h3 class="text-xl font-bold text-ink">{@user.username || @user.telegram_first_name}</h3>
            <p class="text-sm text-ink-muted">ID {@user.id} · tg:{@user.telegram_id}</p>
          </div>
          <button
            type="button"
            phx-click="close"
            class="rounded-md p-1 text-ink-muted hover:bg-surface-hover"
          >
            <.icon name="hero-x-mark" class="size-5" />
          </button>
        </div>

        <div class="mt-4 grid grid-cols-2 gap-3">
          <.stat_card
            icon="hero-bolt"
            tone="info"
            label="Credit chính"
            value={Integer.to_string(main_credits(@user))}
          />
          <.stat_card
            icon="hero-calendar-days"
            tone="success"
            label="Ngày còn lại"
            value={Integer.to_string(main_days(@user))}
          />
        </div>

        <div class="mt-5">
          <p class="text-sm font-semibold text-ink">Điều chỉnh credit</p>
          <form phx-submit="adjust_credit" class="mt-2 flex items-center gap-2">
            <input
              name="amount"
              type="number"
              value="100"
              min="1"
              class="h-9 min-w-0 flex-1 rounded-button border border-line bg-surface px-3 text-sm text-ink shadow-soft focus:border-accent focus:outline-none focus:ring-2 focus:ring-accent/30"
            />
            <.button name="op" value="add">Cộng</.button>
            <.button name="op" value="subtract" variant="secondary">Trừ</.button>
          </form>
        </div>

        <div class="mt-5">
          <p class="text-sm font-semibold text-ink">
            Điều chỉnh credit Index
            <span class="ml-1 font-normal text-ink-muted">(hiện {index_credits(@user)})</span>
          </p>
          <form phx-submit="adjust_index_credit" class="mt-2 flex items-center gap-2">
            <input
              name="amount"
              type="number"
              value="100"
              min="1"
              class="h-9 min-w-0 flex-1 rounded-button border border-line bg-surface px-3 text-sm text-ink shadow-soft focus:border-accent focus:outline-none focus:ring-2 focus:ring-accent/30"
            />
            <.button name="op" value="add">Cộng</.button>
            <.button name="op" value="subtract" variant="secondary">Trừ</.button>
          </form>
        </div>

        <div class="mt-5">
          <p class="text-sm font-semibold text-ink">
            Số ngày còn lại
            <span class="ml-1 font-normal text-ink-muted">(hiện {main_days(@user)})</span>
          </p>
          <p class="mt-0.5 text-xs text-ink-light">Đặt trực tiếp, không phụ thuộc gói.</p>
          <form phx-submit="set_days" class="mt-2 flex items-center gap-2">
            <input
              name="days"
              type="number"
              value={main_days(@user)}
              min="0"
              class="h-9 min-w-0 flex-1 rounded-button border border-line bg-surface px-3 text-sm text-ink shadow-soft focus:border-accent focus:outline-none focus:ring-2 focus:ring-accent/30"
            />
            <.button>Đặt ngày</.button>
          </form>
        </div>

        <div class="mt-5">
          <p class="text-sm font-semibold text-ink">Áp dụng gói (nâng cấp)</p>
          <form phx-change="apply_package" class="mt-2">
            <select
              name="package_id"
              class="block w-full rounded-button border border-line bg-surface px-3 py-2 text-sm text-ink shadow-soft focus:border-accent focus:outline-none focus:ring-2 focus:ring-accent/30"
            >
              <option value="">Chọn gói...</option>
              <option :for={p <- @packages} value={p.id}>
                {p.name} ({p.credits} credit, {p.days} ngày)
              </option>
            </select>
          </form>
        </div>

        <div class="mt-5">
          <p class="text-sm font-semibold text-ink">Mật khẩu</p>
          <p
            :if={@new_password}
            class="mt-1 rounded-button border border-success-border bg-success-bg px-3 py-2 text-sm text-success"
          >
            Mật khẩu mới: <span class="font-mono font-semibold">{@new_password}</span>
          </p>
          <.button type="button" variant="secondary" class="mt-2" phx-click="reset_password">
            Đặt lại mật khẩu
          </.button>
        </div>

        <div class="mt-5 border-t border-line pt-4">
          <p class="text-sm font-semibold text-ink">Hồ sơ</p>
          <.form for={@profile_form} phx-submit="save_profile" class="mt-2 space-y-1">
            <.input field={@profile_form[:username]} label="Username" />
            <.input field={@profile_form[:telegram_first_name]} label="Tên Telegram" />
            <.input field={@profile_form[:telegram_username]} label="Username Telegram" />
            <.button variant="primary" class="mt-2">Lưu hồ sơ</.button>
          </.form>
        </div>

        <div class="mt-5 flex items-center gap-3 border-t border-line pt-4">
          <.button
            :if={@user.status == :active}
            type="button"
            variant="secondary"
            phx-click="ban"
            data-confirm="Khóa người dùng này?"
          >
            Khóa
          </.button>
          <.button :if={@user.status == :banned} type="button" variant="secondary" phx-click="unban">
            Mở khóa
          </.button>
          <.button
            type="button"
            variant="danger"
            phx-click="delete"
            data-confirm="Xóa vĩnh viễn người dùng này?"
          >
            Xóa
          </.button>
        </div>
      </div>
    </div>
    """
  end

  ## Display helpers

  defp main_wallet(user), do: Enum.find(user.wallets || [], &(&1.kind == :main))
  defp index_wallet(user), do: Enum.find(user.wallets || [], &(&1.kind == :index))

  defp credits(user), do: (main_wallet(user) && main_wallet(user).credits) || 0
  defp main_credits(user), do: credits(user)
  defp index_credits(user), do: (index_wallet(user) && index_wallet(user).credits) || 0

  defp days(user) do
    case main_wallet(user) do
      nil -> 0
      wallet -> Billing.days_remaining(wallet)
    end
  end

  defp main_days(user), do: days(user)

  defp tier(user) do
    case main_wallet(user) do
      %{current_package: %{name: name}} -> name
      _ -> "Miễn phí"
    end
  end

  defp status_label(:active), do: "Hoạt động"
  defp status_label(:banned), do: "Bị khóa"
  defp status_label(other), do: to_string(other)
end
