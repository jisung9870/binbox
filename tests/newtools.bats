#!/usr/bin/env bats
# 신규 유틸리티(gbr/glog/klog/kexec/kpf/awsp/assm) 인자 검증 테스트
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
  for tool in gbr glog klog kexec kpf awsp assm; do
    run "$BINBOX_DIR/libexec/$tool" -h
    [ "$status" -eq 0 ]
  done
}

@test "gbr: errors outside a git repo" {
  dir=$(mktemp -d)
  run bash -c "cd '$dir' && GIT_CEILING_DIRECTORIES='$dir' '$BINBOX_DIR/libexec/gbr' 2>&1"
  [ "$status" -eq 1 ]
  [[ "$output" == *"git 저장소"* ]]
  rm -rf "$dir"
}

@test "gbr <branch>: switches directly without fzf" {
  repo=$(mktemp -d)
  git -C "$repo" init -q -b main
  git -C "$repo" -c user.email=t@t -c user.name=t commit --allow-empty -qm init
  git -C "$repo" branch feature
  run bash -c "cd '$repo' && '$BINBOX_DIR/libexec/gbr' feature && git branch --show-current"
  [ "$status" -eq 0 ]
  [[ "$output" == *"feature"* ]]
  rm -rf "$repo"
}

@test "klog: unknown option errors" {
  run "$BINBOX_DIR/libexec/klog" --bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"알 수 없는 옵션"* ]]
}

@test "klog: --tail requires a number" {
  run "$BINBOX_DIR/libexec/klog" --tail abc
  [ "$status" -eq 1 ]
}

@test "kpf: -n requires a value" {
  run "$BINBOX_DIR/libexec/kpf" -n
  [ "$status" -eq 1 ]
}

@test "awsp -h: prints usage to stdout" {
  run bash -c "'$BINBOX_DIR/libexec/awsp' -h 2>/dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" == *"사용법"* ]]
}

@test "awsp <profile>: nonexistent profile errors" {
  export HOME="$STUB_DIR"
  mkdir -p "$STUB_DIR/.aws"
  printf '[profile dev]\nregion=ap-northeast-2\n' > "$STUB_DIR/.aws/config"
  run env PATH="/usr/bin:/bin" "$BINBOX_DIR/libexec/awsp" no-such-profile
  [ "$status" -eq 1 ]
  [[ "$output" == *"존재하지 않는 profile"* ]]
}

@test "awsp <profile>: valid profile prints export line" {
  export HOME="$STUB_DIR"
  mkdir -p "$STUB_DIR/.aws"
  printf '[profile dev]\nregion=ap-northeast-2\n' > "$STUB_DIR/.aws/config"
  run env PATH="/usr/bin:/bin" "$BINBOX_DIR/libexec/awsp" dev
  [ "$status" -eq 0 ]
  [[ "$output" == *"export AWS_PROFILE=dev"* ]]
}

@test "awsp -r <profile>: exports AWS_REGION too" {
  export HOME="$STUB_DIR"
  mkdir -p "$STUB_DIR/.aws"
  printf '[profile dev]\nregion = ap-northeast-2\n' > "$STUB_DIR/.aws/config"
  run env PATH="/usr/bin:/bin" "$BINBOX_DIR/libexec/awsp" -r dev
  [ "$status" -eq 0 ]
  [[ "$output" == *"export AWS_PROFILE=dev"* ]]
  [[ "$output" == *"export AWS_REGION=ap-northeast-2"* ]]
}

@test "awsp -r: profile without region errors" {
  export HOME="$STUB_DIR"
  mkdir -p "$STUB_DIR/.aws"
  printf '[profile dev]\noutput = json\n' > "$STUB_DIR/.aws/config"
  run env PATH="/usr/bin:/bin" "$BINBOX_DIR/libexec/awsp" -r dev
  [ "$status" -eq 1 ]
  [[ "$output" == *"region이 설정되어 있지 않습니다"* ]]
}

@test "assm: missing aws cli errors with hint" {
  run env PATH="/usr/bin:/bin" "$BINBOX_DIR/libexec/assm" 2>&1
  [ "$status" -eq 1 ]
  [[ "$output" == *"aws"* ]]
}
