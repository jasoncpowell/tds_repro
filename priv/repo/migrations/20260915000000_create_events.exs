defmodule TdsRepro.Repo.Migrations.CreateEvents do
  use Ecto.Migration

  def change do
    create table(:events) do
      add :name, :string
      add :happened_on, :date
      add :starts_at, :time
      add :happened_at, :naive_datetime
    end
  end
end
