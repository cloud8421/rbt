defmodule Rbt.Producer.Event do
  defstruct topic: nil,
            data: %{},
            opts: []

  @default_opts [
    headers: [retry_count: 0],
    persistent: false
  ]

  def new(topic, event_data, opts) do
    %__MODULE__{
      topic: topic,
      data: event_data,
      opts: Keyword.merge(@default_opts, opts)
    }
  end
end
