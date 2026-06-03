defmodule SeovivuWeb.Time do
  @moduledoc """
  Display helpers that render stored UTC timestamps in the application's local
  timezone (Asia/Ho_Chi_Minh). Timestamps are always stored in UTC; only the
  presentation is localized.
  """

  @zone "Asia/Ho_Chi_Minh"

  @doc "The application display timezone."
  def zone, do: @zone

  @doc "Shifts a UTC `DateTime` to the local zone (returns nil for nil)."
  def to_local(nil), do: nil

  def to_local(%DateTime{} = dt) do
    case DateTime.shift_zone(dt, @zone) do
      {:ok, local} -> local
      {:error, _} -> dt
    end
  end

  @doc ~S"""
  Formats a UTC `DateTime` in local time. Default format `"%d/%m/%Y %H:%M"`;
  returns `"-"` for nil.
  """
  def datetime(dt, format \\ "%d/%m/%Y %H:%M")
  def datetime(nil, _format), do: "-"
  def datetime(%DateTime{} = dt, format), do: dt |> to_local() |> Calendar.strftime(format)

  @doc "Formats a UTC `DateTime` as a local date `dd/mm/yyyy`."
  def date(dt), do: datetime(dt, "%d/%m/%Y")
end
