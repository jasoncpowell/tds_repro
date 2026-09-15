defmodule TdsRepro.AllTypes do
  @moduledoc """
  One nullable column for each combination of Ecto field type and SQL Server
  column type that the test suite writes nil to. The table is created by the
  `CreateAllTypes` migration.
  """
  use Ecto.Schema

  # {field, Ecto type, column type, sample non-nil value}
  @columns [
    # Column types Ecto's migrations create for these field types
    {:integer_int, :integer, "int", 1},
    {:id_bigint, :id, "bigint", 1},
    {:boolean_bit, :boolean, "bit", true},
    {:decimal_decimal, :decimal, "decimal(10,2)", Decimal.new("1.50")},
    {:string_nvarchar, :string, "nvarchar(255)", "a"},
    {:string_nvarchar_max, :string, "nvarchar(max)", "a"},
    {:binary_varbinary, :binary, "varbinary(max)", <<0, 1, 2>>},
    {:binary_id_uniqueidentifier, :binary_id, "uniqueidentifier",
     "6a2f41a3-c54c-fce8-32d2-0324e1c32e22"},
    {:map_nvarchar_max, :map, "nvarchar(max)", %{"a" => 1}},
    {:float_float, :float, "float", 1.5},
    {:date_date, :date, "date", ~D[2026-01-01]},
    {:time_time, :time, "time(0)", ~T[09:30:00]},
    {:time_usec_time, :time_usec, "time(6)", ~T[09:30:00.123456]},
    {:naive_datetime_datetime, :naive_datetime, "datetime", ~N[2026-01-01 09:30:00]},
    {:naive_datetime_usec_datetime2, :naive_datetime_usec, "datetime2(6)",
     ~N[2026-01-01 09:30:00.123456]},
    {:utc_datetime_datetime, :utc_datetime, "datetime", ~U[2026-01-01 09:30:00Z]},
    {:utc_datetime_usec_datetime2, :utc_datetime_usec, "datetime2(6)",
     ~U[2026-01-01 09:30:00.123456Z]},

    # Other column types found in hand-written or older schemas
    {:decimal_money, :decimal, "money", Decimal.new("1.50")},
    {:string_varchar, :string, "varchar(255)", "a"},
    {:string_text, :string, "text", "a"},
    {:string_ntext, :string, "ntext", "a"},
    {:binary_image, :binary, "image", <<0, 1, 2>>},
    {:float_real, :float, "real", 1.5},
    {:naive_datetime_smalldatetime, :naive_datetime, "smalldatetime", ~N[2026-01-01 09:30:00]},
    {:utc_datetime_usec_datetimeoffset, :utc_datetime_usec, "datetimeoffset",
     ~U[2026-01-01 09:30:00.123456Z]}
  ]

  @doc "The `{field, ecto_type, column_type, sample_value}` combinations."
  def columns, do: @columns

  schema "all_types" do
    for {name, type, _column, _sample} <- @columns do
      field name, type
    end

    embeds_one :metadata, TdsRepro.Metadata, on_replace: :delete
  end
end
