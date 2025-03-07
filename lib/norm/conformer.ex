defmodule Norm.Conformer do
  @moduledoc false
  # This module provides an api for conforming values and a protocol for
  # conformable types

  def conform(spec, input) do
    # If we get errors then we should convert them to messages. Otherwise
    # we just let good results fall through.
    with {:error, errors} <- Norm.Conformer.Conformable.conform(spec, input, []) do
      {:error, Enum.map(errors, &error_to_msg/1)}
    end
  end

  def error_to_msg(%{path: path, input: input, msg: msg, at: at}) do
    path  = if path == [], do: nil, else: "in: " <> build_path(path)
    at    = if at == nil, do: nil, else: "at: :#{at}"
    val   = "val: #{format_val(input)}"
    fails = "fails: #{msg}"

    [path, at, val, fails]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  defp build_path(keys) do
    keys
    |> Enum.map(&format_val/1)
    |> Enum.join("/")
  end

  defp format_val(nil), do: "nil"
  defp format_val(msg) when is_binary(msg), do: "\"#{msg}\""
  defp format_val(msg) when is_boolean(msg), do: "#{msg}"
  defp format_val(msg) when is_atom(msg), do: ":#{msg}"
  defp format_val(val) when is_map(val), do: inspect val
  defp format_val({:index, i}), do: "[#{i}]"
  defp format_val(msg), do: "#{msg}"


  defprotocol Conformable do
    @moduledoc false
    # Defines a conformable type. Must take the type, current path, and input and
    # return an success tuple with the conformed data or a list of errors.

    def conform(spec, path, input)
  end
end


