.PHONY: check doctor test install ci

check:
	./binbox-check

doctor:
	./binbox-doctor

test:
	@command -v bats >/dev/null || { echo "bats not found. Install: brew install bats-core"; exit 1; }
	bats tests/

install:
	find . -maxdepth 1 -type f ! -name 'Makefile' ! -name '*.md' -exec chmod +x {} \;
	find ./tmux-layouts -maxdepth 1 -type f -exec chmod +x {} \;
	@echo
	@echo 'PATH에 추가하세요 (.zshrc):'
	@echo '  export PATH="$(CURDIR):$$PATH"'

ci: check test
