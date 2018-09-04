defmodule Rbt.Producer.Event do
  defstruct message_id: nil,
            topic: nil,
            data: %{},
            opts: []

  @default_opts [
    headers: [retry_count: 0],
    persistent: false
  ]

  def new(message_id, topic, event_data, opts) do
    %__MODULE__{
      message_id: message_id,
      topic: topic,
      data: event_data,
      opts: Keyword.merge(@default_opts, opts)
    }
  end
end
