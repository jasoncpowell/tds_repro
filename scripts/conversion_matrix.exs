# Which SQL Server column types accept a NULL parameter, depending on the
# type the parameter is declared with. Shows why no single default type for
# an untyped nil can work, and that the typed NULLs the fix sends are safe.
#
#   mix run scripts/conversion_matrix.exs
#
# Needs no tables: each check inserts into a table variable.

alias TdsRepro.Repo

columns = [
  "date",
  "time",
  "datetime2",
  "datetimeoffset",
  "datetime",
  "smalldatetime",
  "float",
  "real",
  "decimal(10,2)",
  "money",
  "bit",
  "int",
  "bigint",
  "uniqueidentifier",
  "nvarchar(50)",
  "varchar(50)",
  "text",
  "ntext",
  "varbinary(50)",
  "image"
]

# :binary is what tds declares an untyped nil as today, :string is the default
# proposed and rejected in elixir-ecto/tds#162, and the rest are what the fix
# sends for nil date, time and float fields.
param_types = [:binary, :string, :date, :time, :datetime2, :datetimeoffset, :float]

check = fn sql, params ->
  case Ecto.Adapters.SQL.query(Repo, sql, params) do
    {:ok, _} -> "ok"
    {:error, %Tds.Error{mssql: %{number: number}}} -> "E#{number}"
    {:error, error} -> "error: " <> Exception.message(error)
  end
end

pad = &String.pad_trailing(to_string(&1), &2)

IO.puts("""
Implicit conversion: INSERT a NULL parameter of each type into each column type.
ok = accepted, E206 / E257 = SQL Server refuses the conversion.
""")

IO.puts(pad.("column", 18) <> Enum.map_join(param_types, &pad.(inspect(&1), 17)))

for column <- columns do
  cells =
    for type <- param_types do
      check.(
        "DECLARE @t TABLE (c #{column} NULL); INSERT INTO @t (c) VALUES (@1)",
        [%Tds.Parameter{name: "@1", value: nil, type: type}]
      )
    end

  IO.puts(pad.(column, 18) <> Enum.map_join(cells, &pad.(&1, 17)))
end

IO.puts("""

Explicit conversion: CAST a varbinary NULL parameter, which is what
`type(^value, ...)` produces for nil on released ecto_sql.
ok = accepted, E529 = SQL Server doesn't allow the cast at all.
""")

for column <- ["date", "time", "datetime2", "datetimeoffset", "float", "real"] do
  params = [%Tds.Parameter{name: "@1", value: nil, type: :binary}]
  IO.puts(pad.(column, 18) <> check.("SELECT CAST(@1 AS #{column})", params))
end
