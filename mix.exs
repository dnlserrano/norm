defmodule Norm.MixProject do
  use Mix.Project

  @version "0.2.0"

  def project do
    [
      app: :norm,
      version: @version,
      elixir: "~> 1.7",
      start_permanent: Mix.env() == :prod,
      deps: deps(),

      description: description(),
      package: package(),
      name: "Norm",
      source_url: "https://github.com/keathley/norm",
      docs: docs(),
    ]
  end

  def application do
    []
  end

  defp deps do
    [
      {:stream_data, "~> 0.4.3", optional: true, only: [:dev, :test]},
      {:ex_doc, "~> 0.19", only: [:dev, :test]},
      {:exavier, "~> 0.1.1"}
    ]
  end

  def description do
    """
    Norm is a system for specifying the structure of data. It can be used for
    validation and for generation of data. Norm does not provide any set of
    predicates and instead allows you to re-use any of your existing
    validations.
    """
  end

  def package do
    [
      name: "norm",
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/keathley/norm"},
    ]
  end

  def docs do
    [
      source_ref: "v#{@version}",
      source_url: "https://github.com/keathley/norm",
      main: "Norm",
    ]
  end
end
