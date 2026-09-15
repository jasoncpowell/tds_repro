defmodule TdsRepro.MixProject do
  use Mix.Project

  def project do
    [
      app: :tds_repro,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {TdsRepro.Application, []}
    ]
  end

  defp deps do
    [
      {:ecto_sql, "~> 3.13"},
      {:tds, "~> 2.3"}
    ]
  end
end
