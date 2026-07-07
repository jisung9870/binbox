#!/usr/bin/env bats
# wenv (프리셋 환경 전환) 테스트
# NOTE: bats가 멀티바이트 테스트명을 처리하지 못해 테스트명은 영문 사용

load helpers/stub

setup() {
  BINBOX_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  WENV="$BINBOX_DIR/libexec/wenv"
  setup_stub_dir
  export BINBOX_WENV_DIR="$STUB_DIR/wenv.d"
  mkdir -p "$BINBOX_WENV_DIR"
}

teardown() {
  teardown_stub_dir
}

write_preset() { # write_preset <이름> <내용...>
  local name="$1"
  shift
  printf '%s\n' "$@" > "$BINBOX_WENV_DIR/$name"
}

@test "wenv -h: exits 0 with usage" {
  run "$WENV" -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"사용법"* ]]
}

@test "wenv <preset>: outputs export statements" {
  write_preset dev 'AWS_PROFILE=dev-profile' 'AWS_REGION=ap-northeast-2'
  run "$WENV" dev
  [ "$status" -eq 0 ]
  [[ "$output" == *"export AWS_PROFILE=dev-profile"* ]]
  [[ "$output" == *"export AWS_REGION=ap-northeast-2"* ]]
  [[ "$output" == *"프리셋 적용됨: dev"* ]]
}

@test "wenv: missing preset dies with guidance" {
  run "$WENV" nope
  [ "$status" -eq 1 ]
  [[ "$output" == *"프리셋이 없습니다"* ]]
}

@test "wenv: kube context and namespace call kubectl" {
  make_stub kubectl "printf '%s\n' \"\$*\" >> '$STUB_DIR/kubectl.calls'"
  write_preset k8s 'KUBE_CONTEXT=my-cluster' 'KUBE_NAMESPACE=my-ns'
  run "$WENV" k8s
  [ "$status" -eq 0 ]
  grep -q "config use-context my-cluster" "$STUB_DIR/kubectl.calls"
  grep -q "config set-context --current --namespace my-ns" "$STUB_DIR/kubectl.calls"
}

@test "wenv: EXPORTS entries are exported with escaping" {
  write_preset extra 'EXPORTS=(FOO=bar "MSG=hello world")'
  run "$WENV" extra
  [ "$status" -eq 0 ]
  [[ "$output" == *"export FOO=bar"* ]]
  [[ "$output" == *"export MSG=hello"* ]] # %q 이스케이프 (hello\ world)
}

@test "wenv: invalid EXPORTS entry dies" {
  write_preset bad 'EXPORTS=(1BAD=x)'
  run "$WENV" bad
  [ "$status" -eq 1 ]
  [[ "$output" == *"잘못된 EXPORTS"* ]]
}

@test "wenv: empty preset warns" {
  write_preset empty 'AWS_PROFILE=' 'KUBE_CONTEXT='
  run "$WENV" empty
  [ "$status" -eq 0 ]
  [[ "$output" == *"적용할 항목이 없습니다"* ]]
}

@test "wenv: stdout contains only export statements (eval-safe)" {
  make_stub kubectl "printf 'Switched to context\n'"
  write_preset mix 'AWS_PROFILE=p1' 'KUBE_CONTEXT=c1'
  run bash -c "'$WENV' mix 2>/dev/null"
  [ "$status" -eq 0 ]
  while IFS= read -r line; do
    [[ "$line" == export\ * ]]
  done <<<"$output"
}

@test "wenv list: shows preset names" {
  write_preset dev 'AWS_PROFILE=dev'
  write_preset prod 'AWS_PROFILE=prod'
  run "$WENV" list
  [ "$status" -eq 0 ]
  [[ "$output" == *"dev"* ]]
  [[ "$output" == *"prod"* ]]
}

@test "wenv current: prints env status" {
  make_stub kubectl 'echo my-ctx'
  run env AWS_PROFILE=cur-profile "$WENV" current
  [ "$status" -eq 0 ]
  [[ "$output" == *"cur-profile"* ]]
}

@test "wenv new: creates template, rejects duplicate and reserved names" {
  run env EDITOR=true "$WENV" new myenv
  [ "$status" -eq 0 ]
  [ -f "$BINBOX_WENV_DIR/myenv" ]
  grep -q "AWS_PROFILE=" "$BINBOX_WENV_DIR/myenv"
  run env EDITOR=true "$WENV" new myenv
  [ "$status" -eq 1 ]
  [[ "$output" == *"이미 존재"* ]]
  run env EDITOR=true "$WENV" new list
  [ "$status" -eq 1 ]
  [[ "$output" == *"예약어"* ]]
  run env EDITOR=true "$WENV" new "bad name"
  [ "$status" -eq 1 ]
}

@test "wenv rm: y removes preset, n keeps it" {
  write_preset dev 'AWS_PROFILE=dev'
  run bash -c "printf 'n' | '$WENV' rm dev"
  [ "$status" -eq 0 ]
  [ -f "$BINBOX_WENV_DIR/dev" ]
  run bash -c "printf 'y' | '$WENV' rm dev"
  [ "$status" -eq 0 ]
  [ ! -f "$BINBOX_WENV_DIR/dev" ]
}
