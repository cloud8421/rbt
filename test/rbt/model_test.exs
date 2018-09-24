defmodule Rbt.ModelTest do
  use ExUnit.Case, async: true
  use PropCheck
  use PropCheck.StateM

  @vhost_url "amqp://guest:guest@localhost:5672/rbt-test"

  property "produce and consume events" do
    numtests(
      3,
      trap_exit(
        forall cmds <- commands(__MODULE__) do
          {history, state, result} = run_commands(__MODULE__, cmds)

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

  def initial_state do
    {:idle, %{conns: [], consumers: %{}, producers: %{}}}
  end

  def command({:idle, data}) do
    oneof([
      {:call, __MODULE__, :start_tree, [@vhost_url]}
    ])
  end

  def command({:started, data}) do
    oneof([
      {:call, __MODULE__, :publish_message, []}
      # publish message
      # kill connection
      # recover connection
      # pause consumer
      # resume consumer
    ])
  end

  def precondition(_state, {:call, _mod, _fun, _args}), do: true

  def postcondition(_state, {:call, _mod, _fun, _args}, _res), do: true

  def next_state({:idle, _data}, _res, {:call, __MODULE__, :start_tree, [vhost_url]}) do
    new_data = %{
      conns: [:prod_conn, :cons_conn],
      consumers: %{
        "chat -> message.create" => %{
          conn_ref: :cons_conn,
          state: :subscribed,
          exchange_name: "chat",
          queue_name: "message.create",
          routing_keys: ["convo.created"],
          events: []
        },
        "chat -> notification.create" => %{
          conn_ref: :cons_conn,
          state: :subscribed,
          exchange_name: "chat",
          queue_name: "notification.create",
          routing_keys: ["message.created"],
          events: []
        }
      },
      producers: %{
        "chat" => %{conn_ref: :prod_conn, exchange: "chat", state: :active, buffer: []}
      }
    }

    {:started, new_data}
  end

  ################################################################################
  ################################### COMMANDS ###################################
  ################################################################################

  defmodule ModelTestSupervisor do
    use Supervisor

    def start_link(vhost_url) do
      Supervisor.start_link(__MODULE__, vhost_url)
    end

    def init(opts) do
      test_process = Keyword.fetch!(opts, :test_process)
      vhost_url = Keyword.fetch!(opts, :vhost_url)

      children = [
        {Rbt.SpyHandler, test_process},
        {Rbt.Conn, uri: vhost_url, name: :prod_conn},
        {Rbt.Conn, uri: vhost_url, name: :cons_conn},
        {Rbt.Producer, conn_ref: :prod_conn, definitions: %{exchange_name: "chat"}},
        {Rbt.Consumer.Topic,
         conn_ref: :cons_conn,
         handler: Rbt.SpyHandler,
         definitions: %{
           exchange_name: "chat",
           queue_name: "message.create",
           routing_keys: ["convo.created"]
         },
         max_retries: 3},
        {Rbt.Consumer.Topic,
         conn_ref: :cons_conn,
         handler: Rbt.SpyHandler,
         definitions: %{
           exchange_name: "chat",
           queue_name: "notification.create",
           routing_keys: ["message.created"]
         },
         max_retries: 3}
      ]

      Supervisor.init(children, strategy: :one_for_one)
    end
  end

  def start_tree(vhost_url) do
    opts = [
      vhost_url: vhost_url,
      test_process: self()
    ]

    ModelTestSupervisor.start_link(opts)
  end
end
