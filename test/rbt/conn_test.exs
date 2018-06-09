defmodule Rbt.ConnTest do
  use ExUnit.Case, async: true

  alias Rbt.Conn

  describe "uri validation" do
    test "exits when invalid" do
      Process.flag(:trap_exit, true)

      Conn.start_link(1)

      assert_receive {:EXIT, _pid, {:invalid_uri, :expected_string_uri}}
    end

    test "starts when valid" do
      assert {:ok, _pid} = Conn.start_link("amqp://")
    end
  end

  describe "connection open" do
    test "when successful, transition to connected" do
      {:ok, pid} = Conn.start_link("amqp://guest:guest@localhost:5672/rbt-test")

      assert {:connected, %Rbt.Conn{}} = :sys.get_state(pid)
    end

    test "when failing, remain disconnected" do
      {:ok, pid} =
        Conn.start_link(
          "amqp://guest:guest@localhost:5672/rbt-non-existing",
          connection_timeout: 50
        )

      assert {:disconnected, %Rbt.Conn{}} = :sys.get_state(pid)
    end
  end
end
