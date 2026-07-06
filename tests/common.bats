#!/usr/bin/env bats
# lib/common.sh 단위 테스트
# NOTE: bats가 멀티바이트 테스트명을 처리하지 못해 테스트명은 영문 사용

load helpers/stub

setup() {
  BINBOX_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  setup_stub_dir
}

teardown() {
  teardown_stub_dir
}

@test "die: prints message to stderr and exits 1" {
  run bash -c "source '$BINBOX_DIR/lib/common.sh'; die '에러 발생' 2>&1"
  [ "$status" -eq 1 ]
  [[ "$output" == "에러 발생" ]]
}

@test "die: prints nothing to stdout" {
  run bash -c "source '$BINBOX_DIR/lib/common.sh'; die '에러' 2>/dev/null"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "need_cmd: returns 0 for existing command" {
  run bash -c "source '$BINBOX_DIR/lib/common.sh'; need_cmd bash"
  [ "$status" -eq 0 ]
}

@test "need_cmd: missing command errors with hint" {
  run bash -c "source '$BINBOX_DIR/lib/common.sh'; need_cmd no-such-cmd-xyz 'brew install xyz' 2>&1"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no-such-cmd-xyz"* ]]
  [[ "$output" == *"brew install xyz"* ]]
}

@test "sanitize_session: replaces dots and colons with underscores" {
  run bash -c "source '$BINBOX_DIR/lib/common.sh'; sanitize_session 'a.b:c'"
  [ "$status" -eq 0 ]
  [ "$output" = "a_b_c" ]
}

@test "fzf_pick: cancel (exit 130) returns 0 with empty output" {
  make_stub fzf 'exit 130'
  run bash -c "source '$BINBOX_DIR/lib/common.sh'; printf 'a\nb\n' | fzf_pick"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "fzf_pick: passes selection through" {
  make_stub fzf 'echo picked-item'
  run bash -c "source '$BINBOX_DIR/lib/common.sh'; printf 'a\nb\n' | fzf_pick"
  [ "$status" -eq 0 ]
  [ "$output" = "picked-item" ]
}

@test "confirm: y returns 0" {
  run bash -c "source '$BINBOX_DIR/lib/common.sh'; printf 'y' | confirm '계속?' 2>/dev/null"
  [ "$status" -eq 0 ]
}

@test "confirm: n returns 1" {
  run bash -c "source '$BINBOX_DIR/lib/common.sh'; printf 'n' | confirm '계속?' 2>/dev/null"
  [ "$status" -eq 1 ]
}

@test "common.sh: double-source guard works" {
  run bash -c "source '$BINBOX_DIR/lib/common.sh'; source '$BINBOX_DIR/lib/common.sh'; echo ok"
  [ "$status" -eq 0 ]
  [ "$output" = "ok" ]
}
