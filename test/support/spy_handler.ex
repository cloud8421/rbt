defmodule Rbt.SpyHandler do
  use Rbt.Consumer.Handler
  use GenServer

  def start_link(test_process) do
    GenServer.start_link(__MODULE__, test_process, name: __MODULE__)
  end

  def init(test_process) do
    {:ok, test_process}
  end

  def skip?(%{"case" => "skip"}, _meta) do
    GenServer.call(__MODULE__, :skip)
  end

  def skip?(_event, _meta), do: false

  def handle_event(%{"case" => "success"}, _meta) do
    GenServer.call(__MODULE__, :success)
  end

  def handle_event(%{"case" => "no_retry"}, _meta) do
    GenServer.call(__MODULE__, :no_retry)
  end

  def handle_event(payload, _meta) do
    GenServer.call(__MODULE__, {:unexpected_payload, payload})
  end

  def handle_call(:skip, _from, test_process) do
    send(test_process, :skip)
    {:reply, true, test_process}
  end

  def handle_call(:success, _from, test_process) do
    send(test_process, :success)
    {:reply, :ok, test_process}
  end

  def handle_call(:no_retry, _from, test_process) do
    send(test_process, :no_retry)
    {:reply, {:error, :no_retry, :invalid_data}, test_process}
  end

  def handle_call({:unexpected_payload, payload}, _from, test_process) do
    send(test_process, {:unexpected_payload, payload})
    {:reply, :ok, test_process}
  end
end
