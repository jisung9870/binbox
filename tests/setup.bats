#!/usr/bin/env bats
# binbox-setup 테스트 — 심볼릭 링크 + rc 마커 블록 멱등성
# NOTE: bats가 멀티바이트 테스트명을 처리하지 못해 테스트명은 영문 사용

setup() {
  BINBOX_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  FAKEHOME=$(mktemp -d)
}

teardown() {
  rm -rf "$FAKEHOME"
}

run_setup() { # run_setup <SHELL값> [추가 인자...]
  local sh="$1"
  shift
  run env HOME="$FAKEHOME" ZDOTDIR= SHELL="$sh" "$BINBOX_DIR/bb" setup "$@"
}

@test "setup: zsh fresh install creates symlink and .zshrc block" {
  run_setup /bin/zsh
  [ "$status" -eq 0 ]
  [ -L "$FAKEHOME/.local/bin/bb" ]
  [ "$(readlink "$FAKEHOME/.local/bin/bb")" = "$BINBOX_DIR/bb" ]
  grep -qxF '# >>> binbox >>>' "$FAKEHOME/.zshrc"
  grep -qxF '# <<< binbox <<<' "$FAKEHOME/.zshrc"
  grep -qF "$BINBOX_DIR/shell/init.zsh" "$FAKEHOME/.zshrc"
}

@test "setup: bash shell writes .bashrc with init.bash" {
  run_setup /bin/bash
  [ "$status" -eq 0 ]
  grep -qF "$BINBOX_DIR/shell/init.bash" "$FAKEHOME/.bashrc"
  [ ! -e "$FAKEHOME/.zshrc" ]
}

@test "setup: --shell overrides SHELL detection" {
  run_setup /bin/zsh --shell bash
  [ "$status" -eq 0 ]
  grep -qF "$BINBOX_DIR/shell/init.bash" "$FAKEHOME/.bashrc"
  [ ! -e "$FAKEHOME/.zshrc" ]
}

@test "setup: idempotent - second run says up to date and keeps one block" {
  run_setup /bin/zsh
  [ "$status" -eq 0 ]
  before=$(cat "$FAKEHOME/.zshrc")
  run_setup /bin/zsh
  [ "$status" -eq 0 ]
  [[ "$output" == *"이미 최신"* ]]
  [ "$(cat "$FAKEHOME/.zshrc")" = "$before" ]
  [ "$(grep -cxF '# >>> binbox >>>' "$FAKEHOME/.zshrc")" -eq 1 ]
}

@test "setup: refreshes corrupted block in place with backup" {
  run_setup /bin/zsh
  echo "trailing content" >> "$FAKEHOME/.zshrc"
  # 마커 사이 내용 훼손 (init.zsh 라인 제거)
  grep -vF "init.zsh" "$FAKEHOME/.zshrc" > "$FAKEHOME/.zshrc.tmp"
  cat "$FAKEHOME/.zshrc.tmp" > "$FAKEHOME/.zshrc"
  run_setup /bin/zsh
  [ "$status" -eq 0 ]
  [[ "$output" == *"블록 갱신"* ]]
  grep -qF "$BINBOX_DIR/shell/init.zsh" "$FAKEHOME/.zshrc"
  [ "$(grep -cxF '# >>> binbox >>>' "$FAKEHOME/.zshrc")" -eq 1 ]
  [ -f "$FAKEHOME/.zshrc.bak.binbox" ]
  # 블록 뒤의 기존 내용 보존
  grep -qxF "trailing content" "$FAKEHOME/.zshrc"
}

@test "setup: preserves existing rc content and appends block" {
  echo "# my sentinel line" > "$FAKEHOME/.zshrc"
  run_setup /bin/zsh
  [ "$status" -eq 0 ]
  head -1 "$FAKEHOME/.zshrc" | grep -qxF "# my sentinel line"
  grep -qxF '# >>> binbox >>>' "$FAKEHOME/.zshrc"
}

@test "setup: dies on malformed markers without touching rc" {
  run_setup /bin/zsh
  echo '# >>> binbox >>>' >> "$FAKEHOME/.zshrc" # 마커 중복
  before=$(cat "$FAKEHOME/.zshrc")
  run_setup /bin/zsh
  [ "$status" -eq 1 ]
  [[ "$output" == *"마커"* ]]
  [ "$(cat "$FAKEHOME/.zshrc")" = "$before" ]
}

@test "setup: foreign regular file at link path - declines on EOF, replaces on y" {
  mkdir -p "$FAKEHOME/.local/bin"
  echo "not a link" > "$FAKEHOME/.local/bin/bb"
  run env HOME="$FAKEHOME" ZDOTDIR= SHELL=/bin/zsh "$BINBOX_DIR/bb" setup < /dev/null
  [ "$status" -eq 1 ]
  [ -f "$FAKEHOME/.local/bin/bb" ]
  [ ! -L "$FAKEHOME/.local/bin/bb" ]
  run bash -c "echo y | env HOME='$FAKEHOME' ZDOTDIR= SHELL=/bin/zsh '$BINBOX_DIR/bb' setup"
  [ "$status" -eq 0 ]
  [ -L "$FAKEHOME/.local/bin/bb" ]
  ls "$FAKEHOME/.local/bin/"bb.bak.* >/dev/null
}

@test "setup: replaces stale symlink pointing elsewhere" {
  mkdir -p "$FAKEHOME/.local/bin"
  ln -s /nonexistent/old-binbox/bb "$FAKEHOME/.local/bin/bb"
  run_setup /bin/zsh
  [ "$status" -eq 0 ]
  [ "$(readlink "$FAKEHOME/.local/bin/bb")" = "$BINBOX_DIR/bb" ]
}

@test "setup: unsupported SHELL and no rc files dies with --shell guidance" {
  # bash는 SHELL이 없으면 로그인 셸로 채우므로 unset 대신 fish로 미지원 셸을 시뮬레이션
  run_setup /usr/bin/fish
  [ "$status" -eq 1 ]
  [[ "$output" == *"--shell"* ]]
  run_setup /usr/bin/fish --shell bash
  [ "$status" -eq 0 ]
  grep -qF "init.bash" "$FAKEHOME/.bashrc"
}

@test "setup: rc symlink survives block refresh" {
  echo "" > "$FAKEHOME/real-zshrc"
  ln -s "$FAKEHOME/real-zshrc" "$FAKEHOME/.zshrc"
  run_setup /bin/zsh
  [ "$status" -eq 0 ]
  # 블록 훼손 후 갱신 경로 통과
  grep -vF "init.zsh" "$FAKEHOME/real-zshrc" > "$FAKEHOME/tmp" && cat "$FAKEHOME/tmp" > "$FAKEHOME/real-zshrc"
  run_setup /bin/zsh
  [ "$status" -eq 0 ]
  [ -L "$FAKEHOME/.zshrc" ]
  grep -qF "init.zsh" "$FAKEHOME/real-zshrc"
}

@test "setup: rejects invalid --shell value" {
  run_setup /bin/zsh --shell fish
  [ "$status" -eq 1 ]
  [[ "$output" == *"zsh|bash"* ]]
}

@test "init files: syntax is valid" {
  run bash -n "$BINBOX_DIR/shell/init.bash"
  [ "$status" -eq 0 ]
  command -v zsh >/dev/null || skip "zsh not installed"
  run zsh -n "$BINBOX_DIR/shell/init.zsh"
  [ "$status" -eq 0 ]
}

@test "init.bash: restores aliases, awsp function, and bb completion" {
  run bash --norc -c "source '$BINBOX_DIR/shell/init.bash'; alias tm; type -t awsp; complete -p bb"
  [ "$status" -eq 0 ]
  [[ "$output" == *"bb tm"* ]]
  [[ "$output" == *"function"* ]]
  [[ "$output" == *"_bb_complete"* ]]
}

@test "init.zsh: restores aliases and awsp function" {
  command -v zsh >/dev/null || skip "zsh not installed"
  run zsh -f -c "source '$BINBOX_DIR/shell/init.zsh'; alias tm; whence -w awsp"
  [ "$status" -eq 0 ]
  [[ "$output" == *"bb tm"* ]]
  [[ "$output" == *"function"* ]]
}

@test "init.zsh: double sourcing is guarded" {
  command -v zsh >/dev/null || skip "zsh not installed"
  run zsh -f -c "source '$BINBOX_DIR/shell/init.zsh'; source '$BINBOX_DIR/shell/init.zsh'; alias tm"
  [ "$status" -eq 0 ]
  [[ "$output" == *"bb tm"* ]]
}
