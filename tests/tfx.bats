#!/usr/bin/env bats
# tfx (terraform 통합 명령) 테스트 — 구 tfsum/tfapply 테스트 통합 + state 신규
# NOTE: bats가 멀티바이트 테스트명을 처리하지 못해 테스트명은 영문 사용

load helpers/stub

setup() {
  BINBOX_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  TFX="$BINBOX_DIR/libexec/tfx"
  setup_stub_dir
  export XDG_STATE_HOME="$STUB_DIR/state"
  SESSION_FILE="$XDG_STATE_HOME/binbox/tfsession"
  WORK_DIR=$(mktemp -d)
  cd "$WORK_DIR"
  touch tfplan
}

teardown() {
  cd /
  rm -rf "$WORK_DIR"
  teardown_stub_dir
}

# terraform 호출 기록 + show -json은 빈 JSON 반환 (sum 테스트용)
stub_terraform_sum() {
  make_stub terraform 'printf "%s\n" "$@" >> "'"$STUB_DIR"'/terraform.args"; echo "{}"'
  make_stub tf-summarize 'cat >/dev/null; [ "$#" -gt 0 ] && printf "%s\n" "$@" >> "'"$STUB_DIR"'/tf-summarize.args"; exit 0'
}

# terraform 호출을 한 줄씩 기록 (plan/apply/state 테스트용)
stub_terraform_calls() {
  make_stub terraform "printf '%s\n' \"\$*\" >> '$STUB_DIR/terraform.calls'"
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

write_session() {
  # write_session <오프셋(초)> <계정>
  mkdir -p "$(dirname "$SESSION_FILE")"
  printf '%s\t%s\n' "$(( $(date +%s) + $1 ))" "$2" > "$SESSION_FILE"
}

# --- dispatch ---

@test "tfx -h and no args: usage exits 0" {
  run "$TFX" -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"사용법"* ]]
  run "$TFX"
  [ "$status" -eq 0 ]
  [[ "$output" == *"사용법"* ]]
}

@test "tfx: unknown subcommand exits 2" {
  run "$TFX" badcmd
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown subcommand"* ]]
}

# --- plan ---

@test "tfx init: runs terraform init with passthrough args" {
  stub_terraform_calls
  run "$TFX" init -upgrade
  [ "$status" -eq 0 ]
  grep -q "init -upgrade" "$STUB_DIR/terraform.calls"
}

@test "tfx validate: runs terraform validate with passthrough args" {
  stub_terraform_calls
  run "$TFX" validate -no-color
  [ "$status" -eq 0 ]
  grep -q "validate -no-color" "$STUB_DIR/terraform.calls"
}

@test "tfx fmt: runs terraform fmt with passthrough args" {
  stub_terraform_calls
  run "$TFX" fmt -recursive
  [ "$status" -eq 0 ]
  grep -q "fmt -recursive" "$STUB_DIR/terraform.calls"
}

@test "tfx plan: runs terraform plan -out with passthrough args" {
  stub_terraform_calls
  make_stub aws 'exit 1' # 배너 생략 경로
  run "$TFX" plan -var-file=qa.tfvars
  [ "$status" -eq 0 ]
  grep -q "plan -out=tfplan -var-file=qa.tfvars" "$STUB_DIR/terraform.calls"
  [[ "$output" == *"✔ saved"* ]]
}

# --- sum (구 tfsum) ---

@test "tfx sum: unknown mode exits 2" {
  run "$TFX" sum badcmd
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown subcommand"* ]]
}

@test "tfx sum: default summary runs tf-summarize with no flags" {
  stub_terraform_sum
  run "$TFX" sum
  [ "$status" -eq 0 ]
  [ ! -s "$STUB_DIR/tf-summarize.args" ]
}

@test "tfx sum tree: passes -tree flag" {
  stub_terraform_sum
  run "$TFX" sum tree
  [ "$status" -eq 0 ]
  grep -qx -- "-tree" "$STUB_DIR/tf-summarize.args"
}

@test "tfx sum md outfile: passes -md and -out" {
  stub_terraform_sum
  run "$TFX" sum md summary.md
  [ "$status" -eq 0 ]
  grep -qx -- "-md" "$STUB_DIR/tf-summarize.args"
  grep -qx -- "-out=summary.md" "$STUB_DIR/tf-summarize.args"
}

@test "tfx sum md outfile planfile: uses given plan file" {
  stub_terraform_sum
  touch other.tfplan
  run "$TFX" sum md summary.md other.tfplan
  [ "$status" -eq 0 ]
  grep -qx -- "other.tfplan" "$STUB_DIR/terraform.args"
}

@test "tfx sum md a b c: extra args exit 2" {
  stub_terraform_sum
  run "$TFX" sum md a b c
  [ "$status" -eq 2 ]
  [[ "$output" == *"unexpected argument"* ]]
}

@test "tfx sum: missing plan file errors" {
  stub_terraform_sum
  rm tfplan
  run "$TFX" sum tree
  [ "$status" -eq 1 ]
  [[ "$output" == *"plan file not found"* ]]
  [[ "$output" == *"tfx plan"* ]]
}

@test "tfx sum: respects TFPLAN_FILE env var" {
  stub_terraform_sum
  touch qa.tfplan
  run env TFPLAN_FILE=qa.tfplan "$TFX" sum tree
  [ "$status" -eq 0 ]
  grep -qx -- "qa.tfplan" "$STUB_DIR/terraform.args"
}

# --- apply 세션 (구 tfapply) ---

@test "tfx apply: no session refuses to apply" {
  stub_aws
  stub_terraform_calls
  run "$TFX" apply
  [ "$status" -eq 1 ]
  [[ "$output" == *"세션이 없습니다"* ]]
  [ ! -f "$STUB_DIR/terraform.calls" ]
}

@test "tfx session: correct last-4 digits starts session" {
  stub_aws
  stub_terraform_calls
  run bash -c "printf '9012\n' | '$TFX' session 5"
  [ "$status" -eq 0 ]
  [[ "$output" == *"세션 시작됨"* ]]
  [[ "$output" == *"123456789012"* ]]
  grep -q '123456789012' "$SESSION_FILE"
}

@test "tfx session: wrong digits refuses" {
  stub_aws
  stub_terraform_calls
  run bash -c "printf '0000\n' | '$TFX' session"
  [ "$status" -eq 1 ]
  [[ "$output" == *"계정 확인 실패"* ]]
  [ ! -f "$SESSION_FILE" ]
}

@test "tfx apply: valid session applies plan file" {
  stub_aws
  stub_terraform_calls
  write_session 600 123456789012
  touch "$STUB_DIR/plan.out"
  run bash -c "printf 'y' | env TFPLAN_FILE='$STUB_DIR/plan.out' '$TFX' apply"
  [ "$status" -eq 0 ]
  grep -q "apply $STUB_DIR/plan.out" "$STUB_DIR/terraform.calls"
}

@test "tfx apply: passes extra args before plan file" {
  stub_aws
  stub_terraform_calls
  write_session 600 123456789012
  touch "$STUB_DIR/plan.out"
  run bash -c "printf 'y' | env TFPLAN_FILE='$STUB_DIR/plan.out' '$TFX' apply -no-color"
  [ "$status" -eq 0 ]
  grep -q "apply -no-color $STUB_DIR/plan.out" "$STUB_DIR/terraform.calls"
}

@test "tfx apply: n cancels before applying plan file" {
  stub_aws
  stub_terraform_calls
  write_session 600 123456789012
  touch "$STUB_DIR/plan.out"
  run bash -c "printf 'n' | env TFPLAN_FILE='$STUB_DIR/plan.out' '$TFX' apply"
  [ "$status" -eq 0 ]
  [[ "$output" == *"취소했습니다"* ]]
  ! grep -q "apply $STUB_DIR/plan.out" "$STUB_DIR/terraform.calls" 2>/dev/null
}

@test "tfx apply: expired session refuses and removes session file" {
  stub_aws
  stub_terraform_calls
  write_session -10 123456789012
  run "$TFX" apply
  [ "$status" -eq 1 ]
  [[ "$output" == *"만료"* ]]
  [ ! -f "$SESSION_FILE" ]
  [ ! -f "$STUB_DIR/terraform.calls" ]
}

@test "tfx apply: account mismatch refuses" {
  stub_aws
  stub_terraform_calls
  write_session 600 999999999999
  touch "$STUB_DIR/plan.out"
  run env TFPLAN_FILE="$STUB_DIR/plan.out" "$TFX" apply
  [ "$status" -eq 1 ]
  [[ "$output" == *"다릅니다"* ]]
  ! grep -q apply "$STUB_DIR/terraform.calls" 2>/dev/null
}

@test "tfx apply: missing plan file errors" {
  stub_aws
  stub_terraform_calls
  write_session 600 123456789012
  run env TFPLAN_FILE="$STUB_DIR/no-such-plan" "$TFX" apply
  [ "$status" -eq 1 ]
  [[ "$output" == *"plan file not found"* ]]
}

@test "tfx destroy: no session refuses to destroy" {
  stub_aws
  stub_terraform_calls
  run "$TFX" destroy
  [ "$status" -eq 1 ]
  [[ "$output" == *"세션이 없습니다"* ]]
  [ ! -f "$STUB_DIR/terraform.calls" ]
}

@test "tfx destroy: valid session creates destroy plan then applies it" {
  stub_aws
  stub_terraform_calls
  write_session 600 123456789012
  run bash -c "printf 'y' | '$TFX' destroy -var-file=qa.tfvars"
  [ "$status" -eq 0 ]
  grep -q "plan -destroy -out=tfdestroyplan -var-file=qa.tfvars" "$STUB_DIR/terraform.calls"
  grep -q "apply tfdestroyplan" "$STUB_DIR/terraform.calls"
}

@test "tfx destroy: n cancels after creating destroy plan" {
  stub_aws
  stub_terraform_calls
  write_session 600 123456789012
  run bash -c "printf 'n' | '$TFX' destroy -var-file=qa.tfvars"
  [ "$status" -eq 0 ]
  [[ "$output" == *"취소했습니다"* ]]
  grep -q "plan -destroy -out=tfdestroyplan -var-file=qa.tfvars" "$STUB_DIR/terraform.calls"
  ! grep -q "apply tfdestroyplan" "$STUB_DIR/terraform.calls" 2>/dev/null
}

@test "tfx destroy: respects TFDESTROY_PLAN_FILE env var" {
  stub_aws
  stub_terraform_calls
  write_session 600 123456789012
  run bash -c "printf 'y' | env TFDESTROY_PLAN_FILE='$STUB_DIR/destroy.out' '$TFX' destroy"
  [ "$status" -eq 0 ]
  grep -q "plan -destroy -out=$STUB_DIR/destroy.out" "$STUB_DIR/terraform.calls"
  grep -q "apply $STUB_DIR/destroy.out" "$STUB_DIR/terraform.calls"
}

@test "tfx destroy: expired session refuses and removes session file" {
  stub_aws
  stub_terraform_calls
  write_session -10 123456789012
  run "$TFX" destroy
  [ "$status" -eq 1 ]
  [[ "$output" == *"만료"* ]]
  [ ! -f "$SESSION_FILE" ]
  [ ! -f "$STUB_DIR/terraform.calls" ]
}

@test "tfx destroy: account mismatch refuses" {
  stub_aws
  stub_terraform_calls
  write_session 600 999999999999
  run "$TFX" destroy
  [ "$status" -eq 1 ]
  [[ "$output" == *"다릅니다"* ]]
  ! grep -q destroy "$STUB_DIR/terraform.calls" 2>/dev/null
}

@test "tfx destroy: rejects auto approve" {
  stub_aws
  stub_terraform_calls
  write_session 600 123456789012
  run "$TFX" destroy -auto-approve
  [ "$status" -eq 1 ]
  [[ "$output" == *"-auto-approve"* ]]
  ! grep -q destroy "$STUB_DIR/terraform.calls" 2>/dev/null
}

@test "tfx status: reports valid / missing session" {
  run "$TFX" status
  [ "$status" -eq 1 ]
  [[ "$output" == *"세션 없음"* ]]
  write_session 600 123456789012
  run "$TFX" status
  [ "$status" -eq 0 ]
  [[ "$output" == *"세션 유효"* ]]
}

@test "tfx end: removes session" {
  write_session 600 123456789012
  run "$TFX" end
  [ "$status" -eq 0 ]
  [ ! -f "$SESSION_FILE" ]
}

# --- state ---

# state list가 두 리소스를 돌려주고 mv/rm 호출을 기록하는 terraform 스텁
stub_terraform_state() {
  make_stub terraform "
case \"\$*\" in
  'state list') printf 'aws_instance.a\naws_s3_bucket.b\n' ;;
  state\ mv*|state\ rm*) printf '%s\n' \"\$*\" >> '$STUB_DIR/terraform.calls' ;;
esac
"
  make_stub aws 'exit 1' # 배너 생략 경로
}

@test "tfx state list: prints raw list" {
  stub_terraform_state
  run "$TFX" state list
  [ "$status" -eq 0 ]
  [[ "$output" == *"aws_instance.a"* ]]
  [[ "$output" == *"aws_s3_bucket.b"* ]]
}

@test "tfx state: prints fzf-selected address" {
  stub_terraform_state
  make_stub fzf 'head -n1'
  run "$TFX" state
  [ "$status" -eq 0 ]
  [ "$output" = "aws_instance.a" ]
}

@test "tfx state rm: n cancels without removing" {
  stub_terraform_state
  make_stub fzf 'cat' # 다중 선택: 전체
  run bash -c "printf 'n' | '$TFX' state rm"
  [ "$status" -eq 0 ]
  [[ "$output" == *"취소했습니다"* ]]
  [ ! -f "$STUB_DIR/terraform.calls" ]
}

@test "tfx state rm: y removes selected addresses" {
  stub_terraform_state
  make_stub fzf 'cat'
  run bash -c "printf 'y' | '$TFX' state rm"
  [ "$status" -eq 0 ]
  grep -q "state rm aws_instance.a aws_s3_bucket.b" "$STUB_DIR/terraform.calls"
}

@test "tfx state mv: moves after new address and confirm" {
  stub_terraform_state
  make_stub fzf 'head -n1'
  run bash -c "printf 'aws_instance.renamed\ny' | '$TFX' state mv"
  [ "$status" -eq 0 ]
  grep -q "state mv aws_instance.a aws_instance.renamed" "$STUB_DIR/terraform.calls"
}

@test "tfx state mv: empty new address dies" {
  stub_terraform_state
  make_stub fzf 'head -n1'
  run bash -c "printf '\n' | '$TFX' state mv"
  [ "$status" -eq 1 ]
  [[ "$output" == *"비어 있습니다"* ]]
}

@test "tfx state: unknown subcommand exits 2" {
  stub_terraform_state
  run "$TFX" state badcmd
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown state subcommand"* ]]
}

@test "tfx state: empty state dies with message" {
  make_stub terraform 'exit 0' # state list가 빈 출력
  make_stub fzf 'head -n1'
  run "$TFX" state
  [ "$status" -eq 1 ]
  [[ "$output" == *"state가 비어 있습니다"* ]]
}
