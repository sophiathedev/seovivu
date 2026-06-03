import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :seovivu, Seovivu.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "seovivu_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :seovivu, SeovivuWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "g8349hR77OW4sCpY1g5gZL3UL79hl4YimXm5cRqCAf33mmxlJ6/R//CE+PTuMEUR",
  server: false

# Run Oban jobs inline/manually in tests instead of spawning queues.
# Use Oban.Testing helpers (e.g. assert_enqueued/2, Oban.drain_queue/2).
config :seovivu, Oban, testing: :manual

# Don't auto-spawn SEO batch runner tasks (which make real HTTP requests) in
# tests, and don't run the boot-time orphan-job recovery against the sandbox.
config :seovivu, seo_async: false
config :seovivu, recover_jobs_on_boot: false

# In test we don't send emails
config :seovivu, Seovivu.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
