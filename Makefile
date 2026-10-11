.PHONY: lint audit-roms

audit-roms:
	@python3 scripts/audit-rom-candidates.py

lint:
	@for f in scripts/*.sh installer/*.sh; do bash -n "$$f"; done
	@shellcheck -x -S error scripts/*.sh installer/*.sh
	@python3 tests/test_public_hygiene.py
	@python3 tests/test_one_command_installer.py
	@python3 tests/test_installer_simulation.py
	@python3 tests/test_repo_docs.py
	@python3 tests/test_rilproxy_networkinfo.py
	@python3 tests/test_rilproxy_trial_harness.py
