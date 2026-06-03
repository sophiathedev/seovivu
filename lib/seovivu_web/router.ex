defmodule SeovivuWeb.Router do
  use SeovivuWeb, :router

  import SeovivuWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {SeovivuWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :authenticated do
    plug :require_authenticated_user
  end

  pipeline :admin_only do
    plug :require_authenticated_user
    plug :require_admin
  end

  ## Subdomain index.seovivu.com — the "Submit Index" app (separate :index wallet).
  ## Matches index.seovivu.com and index.localhost. Declared BEFORE the default
  ## host routes so the host-constrained "/" wins on the subdomain. Cross-subdomain
  ## session cookie sharing is finalized in Phase 7 (cookie domain + check_origin).

  # Public SSO landing: exchanges a signed hand-off token for this host's session.
  scope "/", SeovivuWeb.Index, host: "index." do
    pipe_through :browser

    get "/sso", SsoController, :create
  end

  scope "/", SeovivuWeb.Index, host: "index." do
    pipe_through [:browser, :authenticated]

    live_session :index_app, on_mount: [{SeovivuWeb.UserAuth, :ensure_authenticated}] do
      live "/", DashboardLive, :index
      live "/projects/:id", ProjectShowLive, :show
    end
  end

  ## Public + auth pages

  scope "/", SeovivuWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    get "/login", SessionController, :new
    post "/login", SessionController, :create

    live_session :public,
      on_mount: [{SeovivuWeb.UserAuth, :redirect_if_authenticated}] do
      live "/register", RegisterLive, :index
    end
  end

  scope "/", SeovivuWeb do
    pipe_through :browser

    get "/", PageController, :home
    delete "/logout", SessionController, :delete
  end

  # Authenticated hand-off to the index subdomain (signs an SSO token, redirects).
  scope "/", SeovivuWeb do
    pipe_through [:browser, :authenticated]

    get "/go/index", IndexHandoffController, :create
  end

  ## Telegram webhook (production update delivery)

  scope "/telegram", SeovivuWeb do
    pipe_through :api

    post "/webhook/:secret", TelegramController, :webhook
  end

  ## Authenticated user dashboard

  scope "/app", SeovivuWeb do
    pipe_through [:browser, :authenticated]

    live_session :user, on_mount: [{SeovivuWeb.UserAuth, :ensure_authenticated}] do
      live "/", OverviewLive, :index
      live "/check-index", CheckIndexLive, :index
      live "/url-status", UrlStatusLive, :index
      live "/backlink", BacklinkLive, :index
      live "/redirect", RedirectLive, :index
      live "/disavow", DisavowLive, :index
      live "/robots", RobotsLive, :index
      live "/history", HistoryLive, :index
    end
  end

  ## Admin

  scope "/admin", SeovivuWeb.Admin, as: :admin do
    pipe_through [:browser, :admin_only]

    live_session :admin, on_mount: [{SeovivuWeb.UserAuth, :ensure_admin}] do
      live "/", OverviewLive, :index
      live "/users", UserManagerLive, :index
      live "/quota", QuotaLive, :index
      live "/concurrency", ConcurrencyLive, :index
      live "/api-proxy", ApiProxyLive, :index
      live "/settings", SettingsLive, :index
      live "/index/projects", IndexProjectsLive, :index
      live "/index/quota", IndexQuotaLive, :index
    end
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:seovivu, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: SeovivuWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
