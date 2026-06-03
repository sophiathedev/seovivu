defmodule Seovivu.Net.Proxy do
  @moduledoc """
  An outbound proxy used to route HTTP for the URL-status, backlink and redirect
  checkers so the VPS origin IP is never exposed. Tested + rotated by
  `Seovivu.Net.ProxyPool`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "proxies" do
    field :protocol, Ecto.Enum, values: [:http, :https, :socks5], default: :http
    field :host, :string
    field :port, :integer
    field :username, :string
    field :password, :string, redact: true
    field :status, Ecto.Enum, values: [:untested, :ok, :failed], default: :untested
    field :last_tested_at, :utc_datetime
    field :last_latency_ms, :integer
    field :active, :boolean, default: true

    timestamps(type: :utc_datetime)
  end

  def changeset(proxy, attrs) do
    proxy
    |> cast(attrs, [:protocol, :host, :port, :username, :password, :active])
    |> validate_required([:protocol, :host, :port])
    |> validate_number(:port, greater_than: 0, less_than: 65_536)
  end

  @doc "Changeset recording the result of a connectivity test."
  def test_result_changeset(proxy, attrs) do
    cast(proxy, attrs, [:status, :last_tested_at, :last_latency_ms])
  end
end
