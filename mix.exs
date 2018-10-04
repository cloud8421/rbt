defmodule Rbt.MixProject do
  use Mix.Project

  @version "0.4.0"
  @description """
  NOT COMPLETE OR PRODUCTION READY. A set of higher level tools to compose RabbitMQ workflows.
  """

  def project do
    [
      app: :rbt,
      version: @version,
      description: @description,
      package: package(),
      version: @version,
      elixir: "~> 1.6",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      source_url: "https://github.com/cloud8421/rbt",
      homepage_url: "https://github.com/cloud8421/rbt",
      docs: docs(),
      deps: deps(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [coveralls: :test],
      dialyzer: [plt_add_apps: [:jason]]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Rbt.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ranch_proxy_protocol, "~> 2.0", override: true},
      {:amqp, "~> 1.0"},
      {:jason, "~> 1.0", optional: true},
      {:dialyxir, "~> 1.0.0-rc.3", only: [:dev], runtime: false},
      {:ex_doc, "~> 0.19", only: :dev, runtime: false},
      {:propcheck, "~> 1.1", only: :test},
      {:excoveralls, "~> 0.10.1", only: :test, runtime: false}
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"},
    ]
  end

  defp package do
    [
      maintainers: ["Claudio Ortolina <cloud8421@gmail.com>"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/cloud8421/rbt"}
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: [
        "README.md",
        "CODE_OF_CONDUCT.md"
      ],
      before_closing_body_tag: &monospace_fix/1,
      source_ref: "v#{@version}",
      source_url: "https://github.com/cloud8421/rbt",
      groups_for_modules: [
        "Conns and Channels": [
          Rbt.Channel,
          Rbt.Conn,
          Rbt.Conn.URI
        ],
        Consumers: [
          Rbt.Consumer,
          Rbt.Consumer.Handler
        ],
        Producers: [
          Rbt.Producer
        ],
        RPC: [
          Rbt.Rpc.Server,
          Rbt.Rpc.Client
        ],
        Instrumentation: ~r/Instrumentation/,
        Introspection: [
          Rbt.Topology
        ],
        Testing: [
          Rbt.Producer.Sandbox
        ],
        Utils: [
          Rbt.Binding,
          Rbt.Backoff,
          Rbt.Data,
          Rbt.UUID
        ]
      ]
    ]
  end

  defp monospace_fix(_) do
    # Some modules include flow charts which don't align properly
    # with the default ExDoc font, so we override it here with a working one.
    """
    <style>
      code {
        font-family: Menlo,Courier,monospace !important;
      }
    </style>
    """
  end
end
