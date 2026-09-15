defmodule TdsRepro.MixProject do
  use Mix.Project

  def project do
    [
      app: :tds_repro,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      # Each ecto_sql gets its own build directory, so switching between them
      # never runs code compiled against the other.
      build_path: if(upstream_ecto_sql?(), do: "_build_upstream", else: "_build"),
      deps: deps(),
      aliases: aliases()
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
      ecto_sql_dep(),
      {:tds, "~> 2.3"}
    ]
  end

  # By default ecto_sql is the vendored copy carrying the fix (see "Vendored
  # ecto_sql" in the README). ECTO_SQL=upstream uses the release from Hex.
  defp ecto_sql_dep do
    if upstream_ecto_sql?() do
      {:ecto_sql, "3.14.0"}
    else
      {:ecto_sql, path: "vendor/ecto_sql"}
    end
  end

  defp upstream_ecto_sql?, do: System.get_env("ECTO_SQL") == "upstream"

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup"],
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"]
    ]
  end
end
