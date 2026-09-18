defmodule TdsRepro.IntDate do
  @moduledoc """
  A custom `Ecto.Type` with the `:date` primitive that stores dates as
  YYYYMMDD integers in an `int` column, a common pattern in legacy databases.

  It shows why the fix leaves custom types alone: Ecto never calls a type's
  `dump/1` for nil, so the adapter can't know that this type stores its
  non-nil values as integers. A NULL declared as `date` would be refused by
  the `int` column, while the untyped NULL sent today is accepted.
  """
  use Ecto.Type

  @impl true
  def type, do: :date

  @impl true
  def cast(%Date{} = date), do: {:ok, date}
  def cast(_), do: :error

  @impl true
  def dump(%Date{} = date), do: {:ok, date.year * 10_000 + date.month * 100 + date.day}
  def dump(_), do: :error

  @impl true
  def load(int) when is_integer(int) do
    case Date.new(div(int, 10_000), int |> div(100) |> rem(100), rem(int, 100)) do
      {:ok, date} -> {:ok, date}
      {:error, _} -> :error
    end
  end

  def load(_), do: :error
end
