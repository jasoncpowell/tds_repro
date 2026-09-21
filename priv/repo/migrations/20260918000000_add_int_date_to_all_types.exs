defmodule TdsRepro.Repo.Migrations.AddIntDateToAllTypes do
  use Ecto.Migration

  # An int column for TdsRepro.IntDate, a custom type with the :date primitive.
  def change do
    alter table(:all_types) do
      add :int_date_int, :integer
    end
  end
end
