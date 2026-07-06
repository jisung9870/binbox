.PHONY: check doctor test install ci

check:
	./libexec/binbox-check

doctor:
	./libexec/binbox-doctor

test:
	@command -v bats >/dev/null || { echo "bats not found. Install: brew install bats-core"; exit 1; }
	bats tests/

install:
	chmod +x ./bb
	find ./libexec ./tmux-layouts -maxdepth 1 -type f -exec chmod +x {} \;
	@echo
	@echo '.zshrc에 추가하세요:'
	@echo '  export PATH="$(CURDIR):$$PATH"'
	@echo '  source $(CURDIR)/aliases.zsh   # 개별 명령(tm, kctx 등) alias 복원'

ci: check test
