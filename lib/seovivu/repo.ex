defmodule Seovivu.Repo do
  use Ecto.Repo,
    otp_app: :seovivu,
    adapter: Ecto.Adapters.Postgres
end
