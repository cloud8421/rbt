# Rbt

Work in progress, not usable yet.

## Guidelines

- Small, explicit and composable building blocks
- Configuration only for compile-time variables (e.g. which JSON decoder to use)
- Always pass down configuration from the top, e.g. application -> supervisor -> single worker
- Always pass options explicitly at start
- Instrumentable
- Smallest possible dependency surface (make as many as possible optional)
- Support multiple mimetypes
- Don't hide APIs, rather provide ways to compose them
- Introspection to see running components at any given time

## Features

- [x] Topic consumers
  - [x] auto retries with backoff
  - [x] forward failures to separate exchange for capture
  - [x] parallelized, bounded message handling
  - [x] instrumentation hooks
  - [x] manual consume/cancel control
  - [x] multiple content types (erlang, json)
- [x] Topic publishers
  - [x] internal buffering in case of disconnection
  - [x] auto-fingerprint of published messages with generated uuid
  - [x] instrumentation hooks
  - [x] multiple content types (erlang, json)
  - [x] test helpers
- [x] RPC server
- [x] RPC client
- [ ] Complete docs
