RMQ_CURL := curl -i -u "guest:guest"
RMQ_API := http://localhost:15672/api

test: rmq-reset
	mix test
.PHONY: test

rmq-reset: rmq-delete rmq-create
.PHONY: rmq-reset

rmq-create:
	$(RMQ_CURL) -X PUT $(RMQ_API)/vhosts/rbt-test
.PHONY: rmq-create

rmq-delete:
	$(RMQ_CURL) -X DELETE $(RMQ_API)/vhosts/rbt-test
.PHONY: rmq-delete

dialyzer-fast:
	mix dialyzer --no-check
.PHONY: dialyzer-fast
