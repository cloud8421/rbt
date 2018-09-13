defmodule Rbt.ProducerTest do
  use ExUnit.Case, async: true
  use PropCheck
  use PropCheck.StateM

  @vhost_url "amqp://guest:guest@localhost:5672/rbt-test"

  # FLOW
  # - Start
  # - Try to connect
  #   - Fail, backoff and retry
  #   - Succeed, is connected
  #     - Flush the buffer
  # - When disconnected, events get buffered
  # - When connected, events get sent to Rabbit
  # - If disconnecting while event gets sent to Rabbit, event gets buffered

  property "producer state machine", [:verbose] do
    numtests(
      5,
      trap_exit(
        forall cmds <- commands(__MODULE__) do
          {:ok, conn_pid} = Rbt.Conn.start_link(@vhost_url, [], :prod_conn)
          {history, state, result} = run_commands(__MODULE__, cmds)

          # maybe_stop_producer(state)
          # |> IO.inspect()

          Rbt.Conn.close(conn_pid)

          (result == :ok)
          |> aggregate(command_names(cmds))
          |> when_fail(
            IO.puts("""
            History: #{inspect(history)}
            State: #{inspect(state)}
            Result: #{inspect(result)}
            """)
          )
        end
      )
    )
  end

  ################################################################################
  #################################### STATE #####################################
  ################################################################################

  def initial_state do
    {:disconnected, %{conn_ref: :prod_conn, exchange_name: nil, producer: nil}}
  end

  ################################################################################
  ################################### COMMANDS ###################################
  ################################################################################

  def command({:disconnected, data}) do
    oneof([
      {:call, __MODULE__, :start_producer, [data.conn_ref, exchange_name()]}
    ])
  end

  def command({:active, data}) do
    oneof([
      {:call, __MODULE__, :publish, [data.exchange_name, topic(), json()]}
    ])
  end

  def start_producer(conn_ref, exchange_name) do
    Rbt.Producer.start_link(conn_ref, %{exchange_name: exchange_name})
  end

  def publish(exchange_name, topic, payload) do
    Rbt.Producer.publish(exchange_name, topic, payload, content_type: "application/json")
  end

  def maybe_stop_producer({_state, %{producer: pid}}) when is_pid(pid) do
    Rbt.Producer.stop(pid)
  end

  def maybe_stop_producer(_state), do: :ok

  ################################################################################
  ################################ PRECONDITIONS #################################
  ################################################################################

  def precondition(_state, {:call, _mod, _fun, _args}) do
    true
  end

  ################################################################################
  ############################## STATE TRANSITIONS ###############################
  ################################################################################

  def next_state({:disconnected, data}, {:ok, pid}, {:call, __MODULE__, :start_producer, _args})
      when is_pid(pid) do
    {:active, %{data | producer: pid}}
  end

  def next_state({:disconnected, data}, _res, {:call, __MODULE__, :start_producer, args}) do
    [_conn_ref, exchange_name] = args
    {:active, %{data | exchange_name: exchange_name}}
  end

  def next_state(state, _res, {:call, _mod, _fun, _args}) do
    state
  end

  ################################################################################
  ################################ POSTCONDITIONS ################################
  ################################################################################

  def postcondition(
        {:disconnected, _data},
        {:call, __MODULE__, :start_producer, _args},
        {:ok, pid}
      ) do
    eventually(
      fn ->
        status = Rbt.Producer.status(pid)
        status.state == :active
      end,
      10,
      200
    )
  end

  def postcondition({:active, _data}, {:call, __MODULE__, :publish, _args}, :ok) do
    true
  end

  ################################################################################
  ################################## GENERATORS ##################################
  ################################################################################

  defp exchange_name(), do: non_blank_string()

  defp topic, do: non_blank_string()

  defp json do
    let j <- vector(5, {non_blank_string(), json_value()}) do
      Enum.into(j, %{})
    end
  end

  defp non_blank_string do
    such_that(key <- utf8(), when: at_least_one_char?(key))
  end

  defp json_value do
    oneof([scalar_value(), list(scalar_value())])
  end

  defp scalar_value do
    oneof([utf8(), integer(), float(), boolean(), nil])
  end

  ################################################################################
  ################################### HELPERS ####################################
  ################################################################################

  def eventually(f, retries \\ 300, sleep \\ 100)
  def eventually(_, 0, _), do: false

  def eventually(f, retries, sleep) do
    result =
      try do
        f.()
      rescue
        _e ->
          false
      end

    case result do
      false ->
        Process.sleep(sleep)
        eventually(f, retries - 1, sleep)

      nil ->
        Process.sleep(sleep)
        eventually(f, retries - 1, sleep)

      other ->
        other
    end
  end

  defp at_least_one_char?(string) do
    string |> String.trim() |> String.length() > 0
  end

  # property "message buffering" do
  #
  # end

  # test "resilience test" do
  #   {:ok, conn} = Rbt.Conn.start_link(@rmq_test_url, [], __MODULE__)
  #
  #   {:ok, pid} = Rbt.Producer.start_link(__MODULE__, %{exchange_name: "producer-exchange"})
  #   ref = Process.monitor(pid)
  #   refute_receive {:DOWN, ^ref, :process, ^pid, _reason}, 300
  #
  #   publish_sample_message(2)
  #
  #   # active connection, buffer remains empty
  #
  #   assert 0 == Rbt.Producer.buffer_size(pid)
  #   assert [] == Rbt.Producer.buffer(pid)
  #
  #   Rbt.Conn.close(conn)
  #
  #   publish_sample_message(3)
  #
  #   # broken connection, buffer fills up
  #
  #   assert 3 == Rbt.Producer.buffer_size(pid)
  #
  #   {:ok, _conn} = Rbt.Conn.start_link(@rmq_test_url, [], __MODULE__)
  #
  #   publish_sample_message(1)
  #
  #   # connection is warming up (in backoff mode), buffer keeps filling up
  #
  #   assert 4 == Rbt.Producer.buffer_size(pid)
  #
  #   publish_sample_message(100)
  #
  #   Process.sleep(100)
  #
  #   # connection active, buffer gets emptied
  #
  #   assert 0 == Rbt.Producer.buffer_size(pid)
  #   assert [] == Rbt.Producer.buffer(pid)
  # end
  #
  # defp publish_sample_message(number_of_times) do
  #   Enum.each(1..number_of_times, fn _ ->
  #     assert :ok ==
  #              Rbt.Producer.publish(
  #                "producer-exchange",
  #                "test.topic",
  #                %{some: "data"},
  #                content_type: "application/json"
  #              )
  #   end)
  # end
end
