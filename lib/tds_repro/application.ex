defmodule TdsRepro.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [TdsRepro.Repo]
    Supervisor.start_link(children, strategy: :one_for_one, name: TdsRepro.Supervisor)
  end
end
