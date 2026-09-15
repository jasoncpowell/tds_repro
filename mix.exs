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
      # Vendored copy of ecto_sql 3.14.0; see "Vendored ecto_sql" in the README.
      {:ecto_sql, path: "vendor/ecto_sql"},
      {:tds, "~> 2.3"}
    ]
  end
end
