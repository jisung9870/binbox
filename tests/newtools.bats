#!/usr/bin/env bats
# 신규 유틸리티(kx/gx/assume/assm) 인자 검증 테스트
# NOTE: bats가 멀티바이트 테스트명을 처리하지 못해 테스트명은 영문 사용

load helpers/stub

setup() {
  BINBOX_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  setup_stub_dir
}

teardown() {
  teardown_stub_dir
}

@test "new tools -h: all exit 0" {
  for tool in kx gx assume assm; do
    run "$BINBOX_DIR/libexec/$tool" -h
    [ "$status" -eq 0 ]
  done
}

@test "gx br: errors outside a git repo" {
  dir=$(mktemp -d)
  run bash -c "cd '$dir' && GIT_CEILING_DIRECTORIES='$dir' '$BINBOX_DIR/libexec/gx' br 2>&1"
  [ "$status" -eq 1 ]
  [[ "$output" == *"git 저장소"* ]]
  rm -rf "$dir"
}

@test "gx br <branch>: switches directly without fzf" {
  repo=$(mktemp -d)
  git -C "$repo" init -q -b main
  git -C "$repo" -c user.email=t@t -c user.name=t commit --allow-empty -qm init
  git -C "$repo" branch feature
  run bash -c "cd '$repo' && '$BINBOX_DIR/libexec/gx' br feature && git branch --show-current"
  [ "$status" -eq 0 ]
  [[ "$output" == *"feature"* ]]
  rm -rf "$repo"
}

@test "kx log: unknown option errors" {
  run "$BINBOX_DIR/libexec/kx" log --bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"알 수 없는 옵션"* ]]
}

@test "kx log: --tail requires a number" {
  run "$BINBOX_DIR/libexec/kx" log --tail abc
  [ "$status" -eq 1 ]
}

@test "kx pf: -n requires a value" {
  run "$BINBOX_DIR/libexec/kx" pf -n
  [ "$status" -eq 1 ]
}

@test "assm: missing aws cli errors with hint" {
  run env PATH="/usr/bin:/bin" "$BINBOX_DIR/libexec/assm" 2>&1
  [ "$status" -eq 1 ]
  [[ "$output" == *"aws"* ]]
}
