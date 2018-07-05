defmodule Rbt.Producer.Event do
  defstruct topic: nil,
            data: %{},
            opts: []

  def new(topic, content_type, event_data, message_id) do
    opts = [
      message_id: message_id,
      content_type: content_type,
      headers: [retry_count: 0]
    ]

    %__MODULE__{
      topic: topic,
      data: event_data,
      opts: opts
    }
  end
end
