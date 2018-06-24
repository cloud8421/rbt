defmodule Rbt.MixProject do
  use Mix.Project

  def project do
    [
      app: :rbt,
      version: "0.1.0",
      elixir: "~> 1.6",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Rbt.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ranch_proxy_protocol,
       github: "cloud8421/ranch_proxy_protocol", ref: "ffcd8c62", override: true},
      {:amqp, "~> 1.0"},
      {:jason, "~> 1.0", optional: true}
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"},
    ]
  end
end
