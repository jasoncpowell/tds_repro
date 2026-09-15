defmodule TdsRepro.Metadata do
  @moduledoc """
  Embedded in `TdsRepro.AllTypes` to check that a nil date inside an embedded
  schema is still saved as JSON.
  """
  use Ecto.Schema

  @primary_key false
  embedded_schema do
    field :note, :string
    field :reviewed_on, :date
  end
end
