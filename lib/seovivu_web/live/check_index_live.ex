defmodule SeovivuWeb.CheckIndexLive do
  @moduledoc """
  Batch "is this URL indexed by Google?" check. Goes direct through ScrapingDog.
  """
  use SeovivuWeb.BatchFeature, feature: :check_index, title: "Kiểm tra Index"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.dashboard
      current_user={@current_user}
      active={:check_index}
      page_title="Kiểm tra Index"
      flash={@flash}
      credits={@credits}
      days={@days}
    >
      <div class="mb-6">
        <h2 class="text-3xl font-bold tracking-tight text-ink">Kiểm tra Index</h2>
        <p class="mt-1 text-ink-muted">
          Kiểm tra hàng loạt URL đã được Google lập chỉ mục hay chưa. Mỗi URL tốn 1 credit.
        </p>
      </div>

      <div class="space-y-6">
        <BatchFeature.url_form
          form={@form}
          feature={@feature}
          pending_count={@pending_count}
          running={running?(@job)}
        />

        <BatchFeature.progress :if={@job} job={@job} />

        <div :if={@job} class="space-y-3">
          <BatchFeature.results_header />
          <.table id="check-index-items" rows={@streams.items}>
            <:col :let={{_id, item}} label="URL">
              <span class="break-all">{item.url}</span>
            </:col>
            <:col :let={{_id, item}} label="Trạng thái">
              <BatchFeature.status_badge status={item.status} />
            </:col>
            <:col :let={{_id, item}} label="Kết quả">{result_label(item)}</:col>
            <:action :let={{id, item}}>
              <BatchFeature.copy_button id={"copy-#{id}"} text={item.url} label="Sao chép URL" />
            </:action>
          </.table>
        </div>

        <BatchFeature.recent_jobs jobs={@jobs} />
      </div>
    </Layouts.dashboard>
    """
  end

  def copy_line(%{url: url, status: :success, result: %{"indexed" => true}}),
    do: "#{url}\tĐã index"

  def copy_line(%{url: url, status: :success, result: %{"indexed" => false}}),
    do: "#{url}\tChưa index"

  def copy_line(%{url: url, status: :failed, result: result}),
    do: "#{url}\tLỗi: #{result["error"] || "lỗi"}"

  def copy_line(%{url: url}), do: "#{url}\t—"

  defp running?(%{status: :running}), do: true
  defp running?(_), do: false

  defp result_label(%{status: :success, result: %{"indexed" => true}}) do
    assigns = %{}
    ~H|<.badge tone="success">Đã index</.badge>|
  end

  defp result_label(%{status: :success, result: %{"indexed" => false}}) do
    assigns = %{}
    ~H|<.badge tone="warning">Chưa index</.badge>|
  end

  defp result_label(%{status: :failed, result: result}) do
    assigns = %{error: result["error"] || "lỗi"}
    ~H|<span class="text-sm text-danger">{@error}</span>|
  end

  defp result_label(_), do: "—"
end
