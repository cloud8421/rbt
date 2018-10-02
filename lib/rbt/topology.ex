defmodule Rbt.Topology do
  @moduledoc """
  Provides functions to inspect the runtime topology of a `rbt` based system.
  """

  @empty_topology %{
    Rbt.Conn => [],
    Rbt.Producer => [],
    Rbt.Consumer => [],
    Rbt.Rpc.Server => [],
    Rbt.Rpc.Client => []
  }
  @topology_modules Map.keys(@empty_topology)

  @doc """
  Returns a map with topology information for all rbt processes
  under the given supervisor.
  """
  def for_supervisor(supervisor) do
    supervisor
    |> Supervisor.which_children()
    |> Enum.reduce(@empty_topology, &collect_topology/2)
  end

  defp collect_topology(child, acc) do
    case child_id(child) do
      {mod, _params} when mod in @topology_modules ->
        topology_info =
          child
          |> get_pid()
          |> mod.topology_info()

        Map.update!(acc, mod, fn current -> [topology_info | current] end)

      _other ->
        acc
    end
  end

  defp child_id(spec), do: elem(spec, 0)

  defp get_pid(spec), do: elem(spec, 1)
end
