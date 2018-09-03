defmodule Rbt.Consumer.DeliverTest do
  use ExUnit.Case, async: true

  alias Rbt.{Data, Consumer.Deliver}

  defmodule Handler do
    use Rbt.Consumer.Handler
    alias Rbt.Data

    def content_type, do: "application/octet-stream"

    def skip?(%{"case" => "skip"}, _meta), do: true
    def skip?(_payload, _meta), do: false

    def handle_event(%{"case" => "success"}, _meta), do: :ok
    def handle_event(%{"case" => "no_retry"}, _meta), do: {:error, :no_retry, :no_retry_reason}
    def handle_event(%{"case" => "retry"}, _meta), do: {:error, :retry, :retry_reason}
    def handle_event(%{"case" => "raise"}, _meta), do: raise(ArgumentError, "raise reason")
    def handle_event(%{"case" => "catch"}, _meta), do: exit(:catch_reason)
  end

  @meta %{content_type: Handler.content_type()}

  describe "successful handling" do
    test "includes original event and execution time" do
      payload = Data.encode!(%{"case" => "success"}, Handler.content_type())

      assert {:ok, %{"case" => "success"}, elapsed_us} =
               Deliver.handle(payload, @meta, %{handler: Handler})

      assert is_integer(elapsed_us)
      assert elapsed_us in 0..10
    end
  end

  describe "error handling" do
    test "no retry" do
      payload = Data.encode!(%{"case" => "no_retry"}, Handler.content_type())

      assert {:error, :no_retry, :no_retry_reason, %{"case" => "no_retry"}} ==
               Deliver.handle(payload, @meta, %{handler: Handler})
    end

    test "retry" do
      payload = Data.encode!(%{"case" => "retry"}, Handler.content_type())

      assert {:error, :retry, :retry_reason, %{"case" => "retry"}} ==
               Deliver.handle(payload, @meta, %{handler: Handler})
    end

    test "raise" do
      payload = Data.encode!(%{"case" => "raise"}, Handler.content_type())

      assert {:error, :retry, %ArgumentError{message: "raise reason"}, %{"case" => "raise"}} ==
               Deliver.handle(payload, @meta, %{handler: Handler})
    end

    test "catch" do
      payload = Data.encode!(%{"case" => "catch"}, Handler.content_type())

      assert {:error, :retry, :catch_reason, %{"case" => "catch"}} ==
               Deliver.handle(payload, @meta, %{handler: Handler})
    end
  end
end
