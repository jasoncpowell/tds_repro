defmodule TdsRepro do
  @moduledoc """
  Reproduction for the Tds adapter NULL/varbinary bug.

  See https://github.com/elixir-ecto/tds/issues/124 and /168.
  """

  import Ecto.Changeset
  alias TdsRepro.{Event, Repo}

  def run do
    Repo.delete_all(Event)

    event =
      attempt("baseline: INSERT with values", fn ->
        %Event{}
        |> change(%{
          name: "launch",
          happened_on: ~D[2026-01-01],
          starts_at: ~T[09:30:00],
          happened_at: ~N[2026-01-01 09:30:00],
          precise_at: ~N[2026-01-01 09:30:00.123456],
          offset_at: ~U[2026-01-01 09:30:00.123456Z]
        })
        |> Repo.insert!()
      end)

    attempt("INSERT with nil temporal fields", fn ->
      %Event{} |> change(%{name: "no dates"}) |> Repo.insert!()
    end)

    for {field, label} <- [
          {:happened_on, "date"},
          {:starts_at, "time"},
          {:happened_at, "naive_datetime  -> datetime"},
          {:precise_at, "naive_datetime_usec -> datetime2"},
          {:offset_at, "utc_datetime_usec   -> datetimeoffset"}
        ] do
      attempt("UPDATE #{label} -> nil", fn ->
        event |> change(%{field => nil}) |> Repo.update!()
      end)
    end

    attempt("workaround: raw UPDATE with typed %Tds.Parameter{}", fn ->
      Ecto.Adapters.SQL.query!(
        Repo,
        "UPDATE events SET happened_on = @1 WHERE id = @2",
        [
          %Tds.Parameter{name: "@1", value: nil, type: :date},
          %Tds.Parameter{name: "@2", value: event.id, type: :integer}
        ]
      )
    end)

    attempt("insert_all with explicit nil date", fn ->
      Repo.insert_all(Event, [%{name: "bulk", happened_on: nil}])
    end)

    :ok
  end

  defp attempt(label, fun) do
    result = fun.()
    IO.puts("  PASS  #{label}")
    result
  rescue
    e ->
      IO.puts("  FAIL  #{label}")
      IO.puts("        #{one_line(e)}")
      nil
  end

  defp one_line(e) do
    e |> Exception.message() |> String.replace(~r/\s+/, " ") |> String.slice(0, 200)
  end
end
