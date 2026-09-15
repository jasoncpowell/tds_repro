defmodule TdsRepro.Event do
  use Ecto.Schema

  schema "events" do
    field :name, :string
    field :happened_on, :date
    field :starts_at, :time
    # -> legacy `datetime` column
    field :happened_at, :naive_datetime
    # -> `datetime2` column
    field :precise_at, :naive_datetime_usec
    # -> `datetimeoffset` column
    field :offset_at, :utc_datetime_usec
  end
end
