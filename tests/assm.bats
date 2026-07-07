#!/usr/bin/env bats
# assm (SSM 셸 접속 / 포트포워딩) 인자 검증 테스트 — aws는 스텁
# NOTE: bats가 멀티바이트 테스트명을 처리하지 못해 테스트명은 영문 사용

load helpers/stub

setup() {
  BINBOX_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  ASSM="$BINBOX_DIR/libexec/assm"
  setup_stub_dir
  make_stub aws # 인자를 aws.args에 기록
  make_stub session-manager-plugin 'exit 0'
}

teardown() {
  teardown_stub_dir
}

@test "assm -h: exits 0 with usage" {
  run "$ASSM" -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"사용법"* ]]
  [[ "$output" == *"pf"* ]]
}

@test "assm <instance-id>: starts shell session directly" {
  run "$ASSM" i-0123456789abcdef0
  [ "$status" -eq 0 ]
  grep -q -- "--target" "$STUB_DIR/aws.args"
  grep -q "i-0123456789abcdef0" "$STUB_DIR/aws.args"
}

@test "assm pf: missing target dies" {
  run "$ASSM" pf
  [ "$status" -eq 1 ]
  [[ "$output" == *"포워딩 대상"* ]]
}

@test "assm pf: invalid port dies" {
  run "$ASSM" pf abc
  [ "$status" -eq 1 ]
  [[ "$output" == *"올바른 포트 번호가 아닙니다"* ]]
  run "$ASSM" pf 99999
  [ "$status" -eq 1 ]
}

@test "assm pf: invalid host dies" {
  run "$ASSM" pf "bad host:80"
  [ "$status" -eq 1 ]
  [[ "$output" == *"올바른 호스트가 아닙니다"* ]]
}

@test "assm pf: invalid local port dies" {
  run "$ASSM" pf i-0123456789abcdef0 8080 abc
  [ "$status" -eq 1 ]
  [[ "$output" == *"올바른 로컬 포트"* ]]
}

@test "assm pf port: uses instance forwarding document" {
  run "$ASSM" pf i-0123456789abcdef0 8080
  [ "$status" -eq 0 ]
  grep -q "AWS-StartPortForwardingSession" "$STUB_DIR/aws.args"
  grep -qF '{"portNumber":["8080"],"localPortNumber":["8080"]}' "$STUB_DIR/aws.args"
}

@test "assm pf host:port local: uses remote host document and local port" {
  run "$ASSM" pf i-0123456789abcdef0 db.internal:5432 15432
  [ "$status" -eq 0 ]
  grep -q "AWS-StartPortForwardingSessionToRemoteHost" "$STUB_DIR/aws.args"
  grep -qF '{"host":["db.internal"],"portNumber":["5432"],"localPortNumber":["15432"]}' "$STUB_DIR/aws.args"
}

@test "assm pf: extra argument dies" {
  run "$ASSM" pf i-0123456789abcdef0 8080 9090 extra
  [ "$status" -eq 1 ]
  [[ "$output" == *"알 수 없는 인자"* ]]
}
