defmodule SeovivuWeb.Index.ProjectShowLive do
  @moduledoc "Detail view of one Submit-Index project (scoped to the owner)."
  use SeovivuWeb, :live_view

  alias Seovivu.{Billing, Indexer}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    user = socket.assigns.current_user

    case Indexer.get_user_project(user.id, id) do
      nil ->
        {:ok, socket |> put_flash(:error, "Không tìm thấy dự án.") |> push_navigate(to: ~p"/")}

      project ->
        {:ok,
         socket
         |> assign(:page_title, project.name)
         |> assign(:credits, index_credits(user.id))
         |> assign(:project, project)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.index
      current_user={@current_user}
      page_title={@project.name}
      flash={@flash}
      credits={@credits}
    >
      <.link
        navigate={~p"/"}
        class="mb-4 inline-flex items-center gap-1 text-sm text-ink-muted hover:text-ink"
      >
        <.icon name="hero-arrow-left" class="size-4" /> Tất cả dự án
      </.link>

      <div class="mb-6 flex items-center gap-3">
        <h2 class="text-3xl font-bold tracking-tight text-ink">{@project.name}</h2>
        <.badge tone={status_tone(@project.status)}>{status_label(@project.status)}</.badge>
      </div>

      <.table id="project-urls" rows={@project.urls}>
        <:col :let={u} label="URL"><span class="break-all">{u.url}</span></:col>
        <:col :let={u} label="Trạng thái">
          <.badge tone={url_tone(u.status)}>{url_label(u.status)}</.badge>
        </:col>
      </.table>
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

  defp url_label(:pending), do: "Chờ"
  defp url_label(:submitted), do: "Đã gửi"
  defp url_label(:done), do: "Hoàn tất"
  defp url_label(:failed), do: "Lỗi"

  defp url_tone(:done), do: "success"
  defp url_tone(:failed), do: "danger"
  defp url_tone(_), do: "neutral"
end
