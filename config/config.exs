# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :seovivu,
  ecto_repos: [Seovivu.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configure Oban for background job processing.
# Queues map a name to its max concurrency. Add Oban.Plugins as needed,
# e.g. Pruner to trim completed jobs and Cron for scheduled jobs.
config :seovivu, Oban,
  engine: Oban.Engines.Basic,
  repo: Seovivu.Repo,
  queues: [default: 10, mailers: 20, events: 50, telegram: 10],
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},
    # Re-test the proxy pool every 6 hours to keep rotation healthy.
    # Cron schedules use the Asia/Ho_Chi_Minh timezone.
    {Oban.Plugins.Cron,
     timezone: "Asia/Ho_Chi_Minh",
     crontab: [
       {"0 */6 * * *", Seovivu.Net.Workers.RetestProxiesWorker},
       # Daily package-expiry sweep at 00:00 (Asia/Ho_Chi_Minh).
       {"0 0 * * *", Seovivu.Billing.Workers.CheckPackagesWorker}
     ]}
  ]

# Use the `tz` library as Elixir's timezone database so DateTime
# operations across time zones (e.g. DateTime.shift_zone/2) work.
config :elixir, :time_zone_database, Tz.TimeZoneDatabase

# Configure the endpoint
config :seovivu, SeovivuWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: SeovivuWeb.ErrorHTML, json: SeovivuWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Seovivu.PubSub,
  live_view: [signing_salt: "zodPKp9b"]

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :seovivu, Seovivu.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  seovivu: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  seovivu: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
