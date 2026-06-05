defmodule SeovivuWeb.RedirectLive do
  @moduledoc """
  Batch 301/302 redirect checker: for each URL, report the HTTP status and the
  immediate redirect target (without following it). Routed through a proxy.
  """
  use SeovivuWeb.BatchFeature, feature: :redirect_301, title: "Trạng thái Redirect 301"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.dashboard
      current_user={@current_user}
      active={:redirect}
      page_title="Trạng thái Redirect 301"
      flash={@flash}
      credits={@credits}
      days={@days}
    >
      <div class="mb-6">
        <h2 class="text-3xl font-bold tracking-tight text-ink">Trạng thái Redirect 301</h2>
        <p class="mt-1 text-ink-muted">
          Kiểm tra hàng loạt URL có chuyển hướng (301/302) hay không và trỏ tới đâu (qua proxy). Mỗi URL tốn 1 credit.
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
          <.table id="redirect-items" rows={@streams.items}>
            <:col :let={{_id, item}} label="URL">
              <span class="break-all">{item.url}</span>
            </:col>
            <:col :let={{_id, item}} label="Trạng thái">
              <BatchFeature.status_badge status={item.status} />
            </:col>
            <:col :let={{_id, item}} label="Mã HTTP">{code_label(item)}</:col>
            <:col :let={{_id, item}} label="Chuyển hướng tới">{location_label(item)}</:col>
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

  def copy_line(%{url: url, status: :success, result: %{"redirect" => true} = result}),
    do: "#{url}\t#{result["http_status"]}\t→ #{result["location"]}"

  def copy_line(%{url: url, status: :success, result: %{"http_status" => code}}),
    do: "#{url}\t#{code}\tkhông chuyển hướng"

  def copy_line(%{url: url, status: :failed, result: result}),
    do: "#{url}\tLỗi: #{result["error"] || "lỗi"}"

  def copy_line(%{url: url}), do: "#{url}\t—"

  defp running?(%{status: :running}), do: true
  defp running?(_), do: false

  defp code_label(%{status: :success, result: %{"http_status" => code, "redirect" => true}}) do
    assigns = %{code: code}
    ~H|<.badge tone="info">{@code}</.badge>|
  end

  defp code_label(%{status: :success, result: %{"http_status" => code}}) do
    assigns = %{code: code}
    ~H|<.badge tone="neutral">{@code}</.badge>|
  end

  defp code_label(%{status: :failed, result: result}) do
    assigns = %{error: result["error"] || "lỗi"}
    ~H|<span class="text-sm text-danger">{@error}</span>|
  end

  defp code_label(_), do: "—"

  defp location_label(%{status: :success, result: %{"location" => loc}})
       when is_binary(loc) and loc != "" do
    assigns = %{loc: loc}
    ~H|<span class="break-all text-sm text-ink">{@loc}</span>|
  end

  defp location_label(_), do: "—"
end
