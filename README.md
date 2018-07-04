# Rbt

Work in progress, not usable yet.

## Features

- [ ] Topic consumers
  - [x] auto retries with backoff
  - [x] forward failures to separate exchange for capture
  - [ ] parallelized, bounded message handling
  - [x] instrumentation hooks
  - [x] manual consume/cancel control
  - [x] multiple content types (erlang, json)
  - [ ] test helpers
- [ ] Topic publishers
  - [x] internal buffering in case of disconnection
  - [x] auto-fingerprint of published messages with generated uuid
  - [x] instrumentation hooks
  - [x] multiple content types (erlang, json)
  - [ ] test helpers
- [ ] RPC server
- [ ] RPC client
- [ ] Complete docs
