defmodule TdsRepro do
  @moduledoc """
  Reproduction for the Ecto/Tds nil parameter bug.

  Writes nil to one column of each relevant type and prints whether the bug
  shows up. `mix run -e "TdsRepro.run()"` uses the vendored ecto_sql with the
  fix; prefix it with `ECTO_SQL=upstream` for released ecto_sql.

  See https://github.com/elixir-ecto/tds/issues/124 and /168.
  """

  import Ecto.Changeset
  alias TdsRepro.{Event, Repo}

  # {field, column type}
  @nil_updates [
    happened_on: "date",
    starts_at: "time",
    tick: "time(6)",
    happened_at: "datetime",
    precise_at: "datetime2",
    offset_at: "datetimeoffset",
    score: "float"
  ]

  def run do
    IO.puts("Using #{ecto_sql_description()}\n")
    Repo.delete_all(Event)

    event =
      Repo.insert!(%Event{
        name: "launch",
        happened_on: ~D[2026-01-01],
        starts_at: ~T[09:30:00],
        tick: ~T[09:30:00.123456],
        happened_at: ~N[2026-01-01 09:30:00],
        precise_at: ~N[2026-01-01 09:30:00.123456],
        offset_at: ~U[2026-01-01 09:30:00.123456Z],
        score: 1.5
      })

    results =
      [
        check("INSERT leaving every date, time and float field nil", fn ->
          Repo.insert!(%Event{name: "no dates"})
        end)
      ] ++
        for {field, column} <- @nil_updates do
          type = Event.__schema__(:type, field)

          check("UPDATE #{inspect(type)} field on a #{column} column to nil", fn ->
            event |> change(%{field => nil}) |> Repo.update!()
          end)
        end ++
        [
          check("insert_all with an explicit nil date", fn ->
            Repo.insert_all(Event, [%{name: "bulk", happened_on: nil}])
          end),
          check("raw UPDATE with a typed %Tds.Parameter{} (what the fix sends)", fn ->
            Ecto.Adapters.SQL.query!(Repo, "UPDATE events SET happened_on = @1 WHERE id = @2", [
              %Tds.Parameter{name: "@1", value: nil, type: :date},
              %Tds.Parameter{name: "@2", value: event.id, type: :integer}
            ])
          end)
        ]

    bugs = Enum.count(results, &(&1 == :bug))
    IO.puts("\n#{bugs} of #{length(results)} writes hit the bug.")
  end

  defp check(label, fun) do
    fun.()
    IO.puts("  works  #{label}")
    :works
  rescue
    error ->
      IO.puts("  BUG    #{label}")
      IO.puts("         #{one_line(error)}")
      :bug
  end

  # Detects the fix by behaviour, so the output can't disagree with what ran.
  defp ecto_sql_description do
    version = Application.spec(:ecto_sql, :vsn)

    case Ecto.Type.adapter_dump(Ecto.Adapters.Tds, :date, nil) do
      {:ok, %Tds.Parameter{}} -> "ecto_sql #{version} with the fix (vendor/ecto_sql)"
      {:ok, nil} -> "ecto_sql #{version} as released (ECTO_SQL=upstream)"
    end
  end

  defp one_line(error) do
    error
    |> Exception.message()
    |> String.replace(~r/\s+/, " ")
    |> String.replace(" Use the CONVERT function to run this query.", "")
  end
end
