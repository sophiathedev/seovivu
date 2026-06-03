defmodule Seovivu.Repo.Migrations.AddOban do
  use Ecto.Migration

  # Migrate to the latest Oban schema version.
  def up, do: Oban.Migration.up()

  # We specify `version: 1` in `down`, ensuring that we'll remove all of Oban's
  # schema, including the `oban_jobs` table.
  def down, do: Oban.Migration.down(version: 1)
end
