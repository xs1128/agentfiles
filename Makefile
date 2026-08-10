.PHONY: test lint

test:
	cd tui && go test ./...
	bash tests/integration.sh

lint:
	bash -n install.sh doctor.sh setup lib/*.sh tests/*.sh
	shellcheck -x install.sh doctor.sh setup lib/*.sh tests/*.sh
	python3 -m py_compile lib/*.py
