#!/usr/bin/env bats
# bb 디스패처 테스트
# NOTE: bats가 멀티바이트 테스트명을 처리하지 못해 테스트명은 영문 사용

load helpers/stub

setup() {
  BINBOX_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  setup_stub_dir
}

teardown() {
  teardown_stub_dir
}

@test "bb: no args prints usage and tool list" {
  run "$BINBOX_DIR/bb"
  [ "$status" -eq 0 ]
  [[ "$output" == *"사용법"* ]]
  [[ "$output" == *"gitroot"* ]]
}

@test "bb -h: exits 0" {
  run "$BINBOX_DIR/bb" -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"사용법"* ]]
}

@test "bb list: contains tools, excludes bb itself" {
  run "$BINBOX_DIR/bb" list
  [ "$status" -eq 0 ]
  [[ "$output" == *"gitroot"* ]]
  [[ "$output" == *"awsp"* ]]
  ! printf '%s\n' "$output" | grep -qx "bb"
}

@test "bb help gitroot: exits 0 with usage" {
  run "$BINBOX_DIR/bb" help gitroot
  [ "$status" -eq 0 ]
  [[ "$output" == *"사용법"* ]]
}

@test "bb: unknown tool errors with tool list" {
  run "$BINBOX_DIR/bb" no-such-tool-xyz
  [ "$status" -eq 1 ]
  [[ "$output" == *"알 수 없는 도구"* ]]
}

@test "bb: rejects path traversal in tool name" {
  run "$BINBOX_DIR/bb" ../bb
  [ "$status" -eq 1 ]
}

@test "bb gitroot: passes args through inside a git repo" {
  repo=$(mktemp -d)
  git -C "$repo" init -q
  run bash -c "cd '$repo' && '$BINBOX_DIR/bb' gitroot"
  [ "$status" -eq 0 ]
  [[ "$output" == *"$(basename "$repo")" ]]
  rm -rf "$repo"
}

@test "bb doctor: maps to binbox-doctor" {
  run "$BINBOX_DIR/bb" doctor
  [[ "$output" == *"binbox doctor"* ]]
}

@test "bb check: maps to binbox-check (shellcheck missing path)" {
  run env PATH="/usr/bin:/bin" "$BINBOX_DIR/bb" check
  [ "$status" -eq 1 ]
  [[ "$output" == *"shellcheck"* ]]
}

@test "bb upgrade: runs git pull --ff-only (stubbed)" {
  make_stub git 'printf "%s\n" "$@" >> "'"$STUB_DIR"'/git.args"; echo stub-head'
  run "$BINBOX_DIR/bb" upgrade
  [ "$status" -eq 0 ]
  grep -q -- "--ff-only" "$STUB_DIR/git.args"
}

@test "bb upgrade: pull failure prints guidance (stubbed)" {
  make_stub git 'case "$*" in *pull*) exit 1 ;; *) echo stub-head ;; esac'
  run "$BINBOX_DIR/bb" upgrade
  [ "$status" -eq 1 ]
  [[ "$output" == *"업데이트 실패"* ]]
}
