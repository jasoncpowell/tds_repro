defmodule TdsRepro.Repo.Migrations.AddScoreAndTickToEvents do
  use Ecto.Migration

  def change do
    alter table(:events) do
      add :score, :float
      add :tick, :time_usec
    end
  end
end
