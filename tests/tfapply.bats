#!/usr/bin/env bats
# tfapply (세션 기반 terraform apply) 테스트
# NOTE: bats가 멀티바이트 테스트명을 처리하지 못해 테스트명은 영문 사용

load helpers/stub

setup() {
  BINBOX_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  setup_stub_dir
  export XDG_STATE_HOME="$STUB_DIR/state"
  SESSION_FILE="$XDG_STATE_HOME/binbox/tfsession"
}

teardown() {
  teardown_stub_dir
}

# STS가 123456789012 계정을 돌려주는 aws 스텁
stub_aws() {
  make_stub aws "
case \"\$*\" in
  *get-caller-identity*) printf '123456789012\tarn:aws:iam::123456789012:user/test\n' ;;
  *'configure get region'*) printf 'ap-northeast-2\n' ;;
esac
"
}

stub_terraform() {
  make_stub terraform "printf '%s\n' \"\$*\" >> '$STUB_DIR/terraform.calls'"
}

write_session() {
  # write_session <오프셋(초)> <계정>
  mkdir -p "$(dirname "$SESSION_FILE")"
  printf '%s\t%s\n' "$(( $(date +%s) + $1 ))" "$2" > "$SESSION_FILE"
}

@test "tfapply -h: exits 0" {
  run "$BINBOX_DIR/libexec/tfapply" -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"사용법"* ]]
}

@test "tfapply: no session refuses to apply" {
  stub_aws
  stub_terraform
  run "$BINBOX_DIR/libexec/tfapply"
  [ "$status" -eq 1 ]
  [[ "$output" == *"세션이 없습니다"* ]]
  [ ! -f "$STUB_DIR/terraform.calls" ]
}

@test "tfapply session: correct last-4 digits starts session" {
  stub_aws
  stub_terraform
  run bash -c "printf '9012\n' | '$BINBOX_DIR/libexec/tfapply' session 5"
  [ "$status" -eq 0 ]
  [[ "$output" == *"세션 시작됨"* ]]
  [[ "$output" == *"123456789012"* ]]
  grep -q '123456789012' "$SESSION_FILE"
}

@test "tfapply session: wrong digits refuses" {
  stub_aws
  stub_terraform
  run bash -c "printf '0000\n' | '$BINBOX_DIR/libexec/tfapply' session"
  [ "$status" -eq 1 ]
  [[ "$output" == *"계정 확인 실패"* ]]
  [ ! -f "$SESSION_FILE" ]
}

@test "tfapply: valid session applies plan file" {
  stub_aws
  stub_terraform
  write_session 600 123456789012
  touch "$STUB_DIR/plan.out"
  run env TFPLAN_FILE="$STUB_DIR/plan.out" "$BINBOX_DIR/libexec/tfapply"
  [ "$status" -eq 0 ]
  grep -q "apply $STUB_DIR/plan.out" "$STUB_DIR/terraform.calls"
}

@test "tfapply: passes extra args before plan file" {
  stub_aws
  stub_terraform
  write_session 600 123456789012
  touch "$STUB_DIR/plan.out"
  run env TFPLAN_FILE="$STUB_DIR/plan.out" "$BINBOX_DIR/libexec/tfapply" -no-color
  [ "$status" -eq 0 ]
  grep -q "apply -no-color $STUB_DIR/plan.out" "$STUB_DIR/terraform.calls"
}

@test "tfapply: expired session refuses and removes session file" {
  stub_aws
  stub_terraform
  write_session -10 123456789012
  run "$BINBOX_DIR/libexec/tfapply"
  [ "$status" -eq 1 ]
  [[ "$output" == *"만료"* ]]
  [ ! -f "$SESSION_FILE" ]
  [ ! -f "$STUB_DIR/terraform.calls" ]
}

@test "tfapply: account mismatch refuses" {
  stub_aws
  stub_terraform
  write_session 600 999999999999
  touch "$STUB_DIR/plan.out"
  run env TFPLAN_FILE="$STUB_DIR/plan.out" "$BINBOX_DIR/libexec/tfapply"
  [ "$status" -eq 1 ]
  [[ "$output" == *"다릅니다"* ]]
  ! grep -q apply "$STUB_DIR/terraform.calls" 2>/dev/null
}

@test "tfapply: missing plan file errors" {
  stub_aws
  stub_terraform
  write_session 600 123456789012
  run env TFPLAN_FILE="$STUB_DIR/no-such-plan" "$BINBOX_DIR/libexec/tfapply"
  [ "$status" -eq 1 ]
  [[ "$output" == *"plan file not found"* ]]
}

@test "tfapply status: reports valid / missing session" {
  run "$BINBOX_DIR/libexec/tfapply" status
  [ "$status" -eq 1 ]
  [[ "$output" == *"세션 없음"* ]]
  write_session 600 123456789012
  run "$BINBOX_DIR/libexec/tfapply" status
  [ "$status" -eq 0 ]
  [[ "$output" == *"세션 유효"* ]]
}

@test "tfapply end: removes session" {
  write_session 600 123456789012
  run "$BINBOX_DIR/libexec/tfapply" end
  [ "$status" -eq 0 ]
  [ ! -f "$SESSION_FILE" ]
}
