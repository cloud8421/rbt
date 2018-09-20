defmodule Rbt.Producer.Event do
  defstruct message_id: nil,
            topic: nil,
            data: %{},
            opts: []

  @default_opts [
    headers: [retry_count: 0],
    persistent: false
  ]

  @type message_id :: String.t()
  @type topic :: String.t()
  @type data :: %{optional(String.t()) => any()}
  @type opts :: Keyword.t()

  @type t :: %__MODULE__{
          message_id: nil | message_id(),
          topic: nil | topic(),
          data: data(),
          opts: opts()
        }

  @spec new(message_id(), topic(), data(), opts()) :: t()
  def new(message_id, topic, data, opts) do
    %__MODULE__{
      message_id: message_id,
      topic: topic,
      data: data,
      opts: Keyword.merge(@default_opts, opts)
    }
  end
end
