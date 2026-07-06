#!/usr/bin/env bats
# sec 시크릿 스토어 테스트 — 실제 age 키로 라운드트립 검증
# NOTE: bats가 멀티바이트 테스트명을 처리하지 못해 테스트명은 영문 사용

load helpers/stub

setup() {
  BINBOX_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  command -v age >/dev/null 2>&1 || skip "age not installed"
  command -v jq >/dev/null 2>&1 || skip "jq not installed"
  setup_stub_dir
  export BINBOX_AGE_KEY="$STUB_DIR/key.txt"
  export BINBOX_SECRETS_FILE="$STUB_DIR/store.age"
  "$BINBOX_DIR/libexec/sec" init >/dev/null 2>&1
}

teardown() {
  teardown_stub_dir
}

@test "sec -h: exits 0" {
  run "$BINBOX_DIR/libexec/sec" -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"age"* ]]
}

@test "sec: no args prints usage and exits 1" {
  run "$BINBOX_DIR/libexec/sec"
  [ "$status" -eq 1 ]
}

@test "sec: unknown command errors" {
  run "$BINBOX_DIR/libexec/sec" bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"알 수 없는 명령"* ]]
}

@test "sec init: refuses to overwrite existing key" {
  run "$BINBOX_DIR/libexec/sec" init
  [ "$status" -eq 1 ]
  [[ "$output" == *"이미"* ]]
}

@test "sec init: key and store are chmod 600" {
  perms=$(stat -f '%Lp' "$BINBOX_AGE_KEY" 2>/dev/null || stat -c '%a' "$BINBOX_AGE_KEY")
  [ "$perms" = "600" ]
  perms=$(stat -f '%Lp' "$BINBOX_SECRETS_FILE" 2>/dev/null || stat -c '%a' "$BINBOX_SECRETS_FILE")
  [ "$perms" = "600" ]
}

@test "sec set/get: round-trips a value via stdin" {
  printf 'hunter2' | "$BINBOX_DIR/libexec/sec" set mydb password
  run "$BINBOX_DIR/libexec/sec" get mydb password
  [ "$status" -eq 0 ]
  [ "$output" = "hunter2" ]
}

@test "sec get: single-field service works without field name" {
  printf 'tok123' | "$BINBOX_DIR/libexec/sec" set gh token
  run "$BINBOX_DIR/libexec/sec" get gh
  [ "$status" -eq 0 ]
  [ "$output" = "tok123" ]
}

@test "sec get: multi-field service without field lists fields and errors" {
  printf 'a' | "$BINBOX_DIR/libexec/sec" set mydb user
  printf 'b' | "$BINBOX_DIR/libexec/sec" set mydb password
  run "$BINBOX_DIR/libexec/sec" get mydb
  [ "$status" -eq 1 ]
  [[ "$output" == *"필드를 지정하세요"* ]]
  [[ "$output" == *"user"* ]]
  [[ "$output" == *"password"* ]]
}

@test "sec get: missing service errors" {
  run "$BINBOX_DIR/libexec/sec" get nope
  [ "$status" -eq 1 ]
  [[ "$output" == *"존재하지 않는 service"* ]]
}

@test "sec get: missing field errors" {
  printf 'v' | "$BINBOX_DIR/libexec/sec" set mydb user
  run "$BINBOX_DIR/libexec/sec" get mydb nofield
  [ "$status" -eq 1 ]
  [[ "$output" == *"존재하지 않는 field"* ]]
}

@test "sec list: shows services but never values" {
  printf 'hunter2' | "$BINBOX_DIR/libexec/sec" set mydb password
  run "$BINBOX_DIR/libexec/sec" list
  [ "$status" -eq 0 ]
  [[ "$output" == *"mydb"* ]]
  [[ "$output" != *"hunter2"* ]]
}

@test "sec list <service>: shows fields but never values" {
  printf 'hunter2' | "$BINBOX_DIR/libexec/sec" set mydb password
  run "$BINBOX_DIR/libexec/sec" list mydb
  [ "$status" -eq 0 ]
  [[ "$output" == *"password"* ]]
  [[ "$output" != *"hunter2"* ]]
}

@test "sec env: prints export lines with sanitized names" {
  printf 'hunter2' | "$BINBOX_DIR/libexec/sec" set my-db api.key
  run "$BINBOX_DIR/libexec/sec" env my-db
  [ "$status" -eq 0 ]
  [[ "$output" == *"export MY_DB_API_KEY=hunter2"* ]]
}

@test "sec set: rejects empty value" {
  run bash -c "printf '' | '$BINBOX_DIR/libexec/sec' set mydb password"
  [ "$status" -eq 1 ]
  [[ "$output" == *"빈 값"* ]]
}

@test "sec set: rejects invalid names" {
  run bash -c "printf 'v' | '$BINBOX_DIR/libexec/sec' set 'bad name' field"
  [ "$status" -eq 1 ]
  [[ "$output" == *"허용"* ]]
}

@test "sec set: multiline value survives round-trip" {
  printf 'line1\nline2' | "$BINBOX_DIR/libexec/sec" set svc key
  run "$BINBOX_DIR/libexec/sec" get svc key
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "line1" ]
  [ "${lines[1]}" = "line2" ]
}

@test "sec rm: deletes a field after confirm" {
  printf 'a' | "$BINBOX_DIR/libexec/sec" set mydb user
  printf 'b' | "$BINBOX_DIR/libexec/sec" set mydb password
  run bash -c "printf 'y' | '$BINBOX_DIR/libexec/sec' rm mydb user"
  [ "$status" -eq 0 ]
  run "$BINBOX_DIR/libexec/sec" get mydb user
  [ "$status" -eq 1 ]
}

@test "sec rm: removing last field removes the service" {
  printf 'tok' | "$BINBOX_DIR/libexec/sec" set gh token
  run bash -c "printf 'y' | '$BINBOX_DIR/libexec/sec' rm gh token"
  [ "$status" -eq 0 ]
  run "$BINBOX_DIR/libexec/sec" list
  [[ "$output" != *"gh"* ]]
}

@test "sec rm: n answer keeps the value" {
  printf 'tok' | "$BINBOX_DIR/libexec/sec" set gh token
  run bash -c "printf 'n' | '$BINBOX_DIR/libexec/sec' rm gh token"
  [ "$status" -eq 0 ]
  run "$BINBOX_DIR/libexec/sec" get gh token
  [ "$output" = "tok" ]
}

@test "sec copy: pipes value to clipboard command without stdout" {
  printf 'hunter2' | "$BINBOX_DIR/libexec/sec" set mydb password
  make_stub pbcopy "cat > \"$STUB_DIR/pbcopy.out\""
  run bash -c "'$BINBOX_DIR/libexec/sec' copy mydb password 2>/dev/null"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(cat "$STUB_DIR/pbcopy.out")" = "hunter2" ]
}

@test "sec: wrong key fails decryption with clear error" {
  printf 'v' | "$BINBOX_DIR/libexec/sec" set mydb user
  age-keygen -o "$STUB_DIR/other.key" 2>/dev/null
  run env BINBOX_AGE_KEY="$STUB_DIR/other.key" "$BINBOX_DIR/libexec/sec" get mydb user
  [ "$status" -eq 1 ]
  [[ "$output" == *"복호화 실패"* ]]
}

@test "sec: missing key with existing store hints at backup" {
  run env BINBOX_AGE_KEY="$STUB_DIR/no-such-key" "$BINBOX_DIR/libexec/sec" list
  [ "$status" -eq 1 ]
  [[ "$output" == *"age.key"* || "$output" == *"백업"* ]]
}

@test "sec edit: invalid JSON is rejected and store stays intact" {
  printf 'hunter2' | "$BINBOX_DIR/libexec/sec" set mydb password
  make_stub break-editor 'echo broken > "$1"'
  run bash -c "printf 'n' | EDITOR='$STUB_DIR/break-editor' '$BINBOX_DIR/libexec/sec' edit"
  [ "$status" -eq 1 ]
  run "$BINBOX_DIR/libexec/sec" get mydb password
  [ "$output" = "hunter2" ]
}
