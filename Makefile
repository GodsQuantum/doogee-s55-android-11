.PHONY: lint

lint:
	@for f in scripts/*.sh; do bash -n "$$f"; done
	@shellcheck -x -S error scripts/*.sh
	@python3 tests/test_public_hygiene.py
