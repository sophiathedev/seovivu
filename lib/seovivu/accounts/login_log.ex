defmodule Seovivu.Accounts.LoginLog do
  @moduledoc "Records each successful login with the originating IP and user agent."
  use Ecto.Schema
  import Ecto.Changeset

  schema "login_logs" do
    field :ip_address, :string
    field :user_agent, :string
    belongs_to :user, Seovivu.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(log, attrs) do
    log
    |> cast(attrs, [:user_id, :ip_address, :user_agent])
    |> validate_required([:user_id])
  end
end
