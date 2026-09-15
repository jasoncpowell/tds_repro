# Runs find_affected_columns.sql against this repo's database and prints the
# result. To check another database, run the .sql file in any SQL Server client.
#
#   mix run scripts/find_affected_columns.exs

sql = File.read!(Path.join(__DIR__, "find_affected_columns.sql"))
%{columns: columns, rows: rows} = Ecto.Adapters.SQL.query!(TdsRepro.Repo, sql, [])

table = [columns | Enum.map(rows, fn row -> Enum.map(row, &to_string/1) end)]

widths =
  table
  |> Enum.zip_with(& &1)
  |> Enum.map(fn cells -> cells |> Enum.map(&String.length/1) |> Enum.max() end)

for row <- table do
  row
  |> Enum.zip_with(widths, &String.pad_trailing/2)
  |> Enum.join("  ")
  |> IO.puts()
end

IO.puts("\n#{length(rows)} column(s) found")
