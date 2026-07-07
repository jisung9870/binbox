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
  [[ "$output" == *"gx"* ]]
}

@test "bb -h: exits 0" {
  run "$BINBOX_DIR/bb" -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"사용법"* ]]
}

@test "bb list: contains tools, excludes bb itself" {
  run "$BINBOX_DIR/bb" list
  [ "$status" -eq 0 ]
  [[ "$output" == *"gx"* ]]
  [[ "$output" == *"kx"* ]]
  [[ "$output" == *"assume"* ]]
  [[ "$output" != *"awsp"* ]]
  ! printf '%s\n' "$output" | grep -qx "bb"
  for old in kctx kns klog kexec kpf gbr glog gitroot; do
    ! printf '%s\n' "$output" | grep -qx "$old"
  done
}

@test "bb help gx: exits 0 with usage" {
  run "$BINBOX_DIR/bb" help gx
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

@test "bb gx root: passes args through inside a git repo" {
  repo=$(mktemp -d)
  git -C "$repo" init -q
  run bash -c "cd '$repo' && '$BINBOX_DIR/bb' gx root"
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

@test "completions: zsh syntax is valid" {
  command -v zsh >/dev/null || skip "zsh not installed"
  for f in "$BINBOX_DIR"/completions/_*; do
    run zsh -n "$f"
    [ "$status" -eq 0 ]
  done
}

@test "bb new: creates executable template that passes -h and shellcheck" {
  tool="zz-bbnew-test-$$"
  run "$BINBOX_DIR/bb" new "$tool"
  [ "$status" -eq 0 ]
  [ -x "$BINBOX_DIR/libexec/$tool" ]
  run "$BINBOX_DIR/libexec/$tool" -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"사용법"* ]]
  run "$BINBOX_DIR/bb" list
  [[ "$output" == *"$tool"* ]]
  if command -v shellcheck >/dev/null; then
    run shellcheck -x -P SCRIPTDIR "$BINBOX_DIR/libexec/$tool"
    [ "$status" -eq 0 ]
  fi
  rm -f "$BINBOX_DIR/libexec/$tool"
}

@test "bb new: rejects existing, reserved, and invalid names" {
  run "$BINBOX_DIR/bb" new tm
  [ "$status" -eq 1 ]
  [[ "$output" == *"이미 존재"* ]]
  run "$BINBOX_DIR/bb" new list
  [ "$status" -eq 1 ]
  [[ "$output" == *"예약어"* ]]
  run "$BINBOX_DIR/bb" new "Bad_Name"
  [ "$status" -eq 1 ]
  run "$BINBOX_DIR/bb" new
  [ "$status" -eq 1 ]
}
