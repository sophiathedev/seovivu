defmodule SeovivuWeb.TelegramController do
  @moduledoc "Receives Telegram webhook updates (production path)."
  use SeovivuWeb, :controller

  alias Seovivu.{Settings, Telegram}

  def webhook(conn, %{"secret" => secret} = params) do
    header = conn |> get_req_header("x-telegram-bot-api-secret-token") |> List.first()
    expected = Settings.get_value("telegram.webhook_secret")

    if authorized?(expected, secret, header) do
      params |> Map.delete("secret") |> Telegram.handle_update()
      json(conn, %{ok: true})
    else
      conn |> put_status(:forbidden) |> json(%{ok: false})
    end
  end

  # The path secret and the Telegram secret-token header are both accepted; at
  # least one must match the stored secret.
  defp authorized?(expected, path_secret, header_secret)
       when is_binary(expected) and expected != "" do
    Plug.Crypto.secure_compare(expected, path_secret || "") or
      Plug.Crypto.secure_compare(expected, header_secret || "")
  end

  defp authorized?(_expected, _path, _header), do: false
end
