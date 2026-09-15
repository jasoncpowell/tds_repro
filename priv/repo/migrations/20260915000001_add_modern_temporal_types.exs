defmodule TdsRepro.Repo.Migrations.AddModernTemporalTypes do
  use Ecto.Migration

  def change do
    alter table(:events) do
      # Raw SQL Server types, to cover the modern temporal family that
      # Ecto's :naive_datetime does not reach (it maps to legacy `datetime`).
      add :precise_at, :datetime2
      add :offset_at, :datetimeoffset
    end
  end
end
