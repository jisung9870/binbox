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
	./bb setup

ci: check test
