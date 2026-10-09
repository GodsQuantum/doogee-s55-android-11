.PHONY: lint audit-roms

audit-roms:
	@python3 scripts/audit-rom-candidates.py

lint:
	@for f in scripts/*.sh; do bash -n "$$f"; done
	@shellcheck -x -S error scripts/*.sh
	@python3 tests/test_public_hygiene.py
