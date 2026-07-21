#!/usr/bin/env bats
# assume (AWS SSO/role profile env 전환) 테스트 — aws는 스텁

load helpers/stub

setup() {
  BINBOX_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  ASSUME="$BINBOX_DIR/libexec/assume"
  setup_stub_dir
  export HOME="$STUB_DIR/home"
  export BINBOX_ASSUME_CACHE_DIR="$STUB_DIR/cache"
  mkdir -p "$HOME/.aws/sso/cache"
  command -v jq >/dev/null || skip "jq not installed"
}

teardown() {
  teardown_stub_dir
}

write_config() {
  mkdir -p "$HOME/.aws"
  printf '%s\n' "$@" > "$HOME/.aws/config"
}

write_credentials() {
  mkdir -p "$HOME/.aws"
  printf '%s\n' "$@" > "$HOME/.aws/credentials"
}

write_sso_token() {
  cat > "$HOME/.aws/sso/cache/token.json" <<'JSON'
{
  "startUrl": "https://example.awsapps.com/start",
  "sessionName": "corp",
  "region": "ap-northeast-2",
  "accessToken": "SSO_TOKEN",
  "expiresAt": "2999-01-01T00:00:00Z"
}
JSON
}

stub_aws_sso() {
  make_stub aws '
printf "%s\n" "$*" >> "$STUB_DIR/aws.calls"
case "$*" in
  "--no-cli-pager sso get-role-credentials"*)
    cat <<JSON
{"roleCredentials":{"accessKeyId":"AKIASSO","secretAccessKey":"SECRETSSO","sessionToken":"TOKENSSO","expiration":32503680000000}}
JSON
    ;;
  "--no-cli-pager sso login"*)
    exit 0
    ;;
  "--no-cli-pager sts get-caller-identity"*)
    printf "123456789012\tarn:aws:sts::123456789012:assumed-role/Test/me\n"
    ;;
  *)
    printf "unexpected aws call: %s\n" "$*" >&2
    exit 2
    ;;
esac
'
}

stub_aws_role() {
  make_stub aws '
printf "%s\n" "$*" >> "$STUB_DIR/aws.calls"
case "$*" in
  "--no-cli-pager sts assume-role"*)
    env | grep -E "^(AWS_ACCESS_KEY_ID|AWS_SECRET_ACCESS_KEY|AWS_SESSION_TOKEN)=" | sort >> "$STUB_DIR/aws.env"
    cat <<JSON
{"Credentials":{"AccessKeyId":"AKIAROLE","SecretAccessKey":"SECRETROLE","SessionToken":"TOKENROLE","Expiration":"2999-01-01T00:00:00Z"}}
JSON
    ;;
  *)
    printf "unexpected aws call: %s\n" "$*" >&2
    exit 2
    ;;
esac
'
}

@test "assume -h: exits 0 with usage" {
  run "$ASSUME" -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"사용법"* ]]
}

@test "assume list: prints config profiles" {
  write_config \
    '[profile dev]' \
    'region = ap-northeast-2' \
    '[sso-session corp]' \
    'sso_start_url = https://example.awsapps.com/start' \
    '[default]' \
    'region = us-east-1'
  run "$ASSUME" list
  [ "$status" -eq 0 ]
  [[ "$output" == *"default"* ]]
  [[ "$output" == *"dev"* ]]
  [[ "$output" != *"corp"* ]]
}

@test "assume sso profile: outputs eval-safe exports and caches credentials" {
  write_config \
    '[profile dev]' \
    'sso_session = corp' \
    'sso_account_id = 123456789012' \
    'sso_role_name = Admin' \
    'region = ap-northeast-2' \
    '[sso-session corp]' \
    'sso_start_url = https://example.awsapps.com/start' \
    'sso_region = ap-northeast-2'
  write_sso_token
  stub_aws_sso

  run bash -c "'$ASSUME' dev 2>/dev/null"
  [ "$status" -eq 0 ]
  while IFS= read -r line; do
    [[ "$line" == export\ * || "$line" == unset\ * ]]
  done <<< "$output"
  [[ "$output" == *"export AWS_ACCESS_KEY_ID=AKIASSO"* ]]
  [[ "$output" == *"export AWS_REGION=ap-northeast-2"* ]]
  [ -f "$BINBOX_ASSUME_CACHE_DIR/dev.json" ]
  grep -q "sso get-role-credentials" "$STUB_DIR/aws.calls"
}

@test "assume sso profile: AWS_CREDENTIAL_EXPIRATION is ISO 8601, not epoch" {
  write_config \
    '[profile dev]' \
    'sso_session = corp' \
    'sso_account_id = 123456789012' \
    'sso_role_name = Admin' \
    'region = ap-northeast-2' \
    '[sso-session corp]' \
    'sso_start_url = https://example.awsapps.com/start' \
    'sso_region = ap-northeast-2'
  write_sso_token
  stub_aws_sso

  run bash -c "'$ASSUME' dev 2>/dev/null"
  [ "$status" -eq 0 ]
  # botocore(EnvProvider)는 ISO 8601만 파싱한다. epoch 정수면 boto3 인증이 깨진다.
  [[ "$output" =~ export\ AWS_CREDENTIAL_EXPIRATION=[0-9]{4}-[0-9]{2}-[0-9]{2}T ]]
  [[ ! "$output" =~ AWS_CREDENTIAL_EXPIRATION=[0-9]+$ ]]
}

@test "assume cache hit: skips aws calls" {
  mkdir -p "$BINBOX_ASSUME_CACHE_DIR"
  cat > "$BINBOX_ASSUME_CACHE_DIR/dev.json" <<JSON
{"AccessKeyId":"AKIACACHED","SecretAccessKey":"SECRETCACHED","SessionToken":"TOKENCACHED","Region":"us-west-2","Expiration":32503680000}
JSON
  chmod 600 "$BINBOX_ASSUME_CACHE_DIR/dev.json"
  write_config \
    '[profile dev]' \
    'sso_start_url = https://example.awsapps.com/start' \
    'sso_region = us-west-2' \
    'sso_account_id = 123456789012' \
    'sso_role_name = Admin'
  make_stub aws 'echo "aws should not be called" >&2; exit 9'

  run bash -c "'$ASSUME' dev 2>/dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" == *"AKIACACHED"* ]]
}

@test "assume --refresh: ignores credential cache" {
  mkdir -p "$BINBOX_ASSUME_CACHE_DIR"
  cat > "$BINBOX_ASSUME_CACHE_DIR/dev.json" <<JSON
{"AccessKeyId":"AKIACACHED","SecretAccessKey":"SECRETCACHED","SessionToken":"TOKENCACHED","Region":"us-west-2","Expiration":32503680000}
JSON
  write_config \
    '[profile dev]' \
    'sso_start_url = https://example.awsapps.com/start' \
    'sso_region = us-west-2' \
    'sso_account_id = 123456789012' \
    'sso_role_name = Admin'
  write_sso_token
  stub_aws_sso

  run bash -c "'$ASSUME' --refresh dev 2>/dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" == *"AKIASSO"* ]]
  grep -q "sso get-role-credentials" "$STUB_DIR/aws.calls"
}

@test "assume role chain: uses source profile credentials for sts assume-role" {
  write_config \
    '[profile admin]' \
    'role_arn = arn:aws:iam::123456789012:role/Admin' \
    'source_profile = base' \
    'region = ap-northeast-2' \
    'duration_seconds = 3600' \
    'external_id = ext-1'
  write_credentials \
    '[base]' \
    'aws_access_key_id = AKIABASE' \
    'aws_secret_access_key = SECRETBASE' \
    'aws_session_token = TOKENBASE'
  stub_aws_role

  run bash -c "'$ASSUME' admin 2>/dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" == *"export AWS_ACCESS_KEY_ID=AKIAROLE"* ]]
  grep -q "sts assume-role" "$STUB_DIR/aws.calls"
  grep -q -- "--external-id ext-1" "$STUB_DIR/aws.calls"
  grep -q "AWS_ACCESS_KEY_ID=AKIABASE" "$STUB_DIR/aws.env"
  [ ! -f "$BINBOX_ASSUME_CACHE_DIR/base.json" ]
}

@test "assume unset: emits unset statements" {
  run "$ASSUME" unset
  [ "$status" -eq 0 ]
  [[ "$output" == *"unset AWS_ACCESS_KEY_ID"* ]]
  [[ "$output" == *"unset BINBOX_ASSUME_PROFILE"* ]]
}

@test "assume exec: runs command with resolved credentials" {
  write_config \
    '[profile dev]' \
    'sso_start_url = https://example.awsapps.com/start' \
    'sso_region = us-west-2' \
    'sso_account_id = 123456789012' \
    'sso_role_name = Admin'
  write_sso_token
  stub_aws_sso

  run "$ASSUME" exec dev -- bash -c 'printf "%s %s\n" "$AWS_ACCESS_KEY_ID" "$BINBOX_ASSUME_PROFILE"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"AKIASSO dev"* ]]
}

@test "assume profile: with no args lists profiles" {
  write_config \
    '[profile dev]' 'region = us-east-1' \
    '[default]' 'region = us-east-1'
  run "$ASSUME" profile
  [ "$status" -eq 0 ]
  [[ "$output" == *"dev"* ]]
  [[ "$output" == *"default"* ]]
}

@test "assume profile add static: keys to credentials, region to config" {
  write_config '[default]' 'region = us-east-1'
  run "$ASSUME" profile add st --type static \
    --access-key-id AKIASTATIC --secret-access-key SECRETSTATIC --region ap-northeast-2
  [ "$status" -eq 0 ]
  grep -q '^\[st\]' "$HOME/.aws/credentials"
  grep -q 'aws_access_key_id = AKIASTATIC' "$HOME/.aws/credentials"
  grep -q 'aws_secret_access_key = SECRETSTATIC' "$HOME/.aws/credentials"
  grep -q '^\[profile st\]' "$HOME/.aws/config"
  grep -q 'region = ap-northeast-2' "$HOME/.aws/config"
}

@test "assume profile add role: writes role_arn and source_profile to config" {
  write_config '[profile base]' 'region = us-east-1'
  run "$ASSUME" profile add app --type role \
    --role-arn arn:aws:iam::111122223333:role/App --source-profile base \
    --region ap-northeast-2 --external-id ext-1
  [ "$status" -eq 0 ]
  grep -q '^\[profile app\]' "$HOME/.aws/config"
  grep -q 'role_arn = arn:aws:iam::111122223333:role/App' "$HOME/.aws/config"
  grep -q 'source_profile = base' "$HOME/.aws/config"
  grep -q 'external_id = ext-1' "$HOME/.aws/config"
}

@test "assume profile add sso: references existing sso-session" {
  write_config \
    '[sso-session corp]' \
    'sso_start_url = https://example.awsapps.com/start' \
    'sso_region = ap-northeast-2'
  run "$ASSUME" profile add prod --type sso --sso-session corp \
    --account-id 123456789012 --role-name Admin --region ap-northeast-2
  [ "$status" -eq 0 ]
  grep -q '^\[profile prod\]' "$HOME/.aws/config"
  grep -q 'sso_session = corp' "$HOME/.aws/config"
  grep -q 'sso_account_id = 123456789012' "$HOME/.aws/config"
  grep -q 'sso_role_name = Admin' "$HOME/.aws/config"
}

@test "assume profile add: duplicate name errors" {
  write_config '[profile dev]' 'region = us-east-1'
  run "$ASSUME" profile add dev --type role \
    --role-arn arn:x --source-profile base --region us-east-1
  [ "$status" -eq 1 ]
  [[ "$output" == *"이미 존재"* ]]
}

@test "assume profile rm -y: removes section and cache" {
  write_config \
    '[profile dev]' 'region = us-east-1' \
    '[profile keep]' 'region = us-east-1'
  mkdir -p "$BINBOX_ASSUME_CACHE_DIR"
  echo '{}' > "$BINBOX_ASSUME_CACHE_DIR/dev.json"
  run "$ASSUME" profile rm dev -y
  [ "$status" -eq 0 ]
  run "$ASSUME" list
  [[ "$output" != *"dev"* ]]
  [[ "$output" == *"keep"* ]]
  [ ! -f "$BINBOX_ASSUME_CACHE_DIR/dev.json" ]
}

@test "assume profile show: prints the profile section" {
  write_config \
    '[profile dev]' \
    'role_arn = arn:aws:iam::111122223333:role/App' \
    'source_profile = base'
  run "$ASSUME" profile show dev
  [ "$status" -eq 0 ]
  [[ "$output" == *"[profile dev]"* ]]
  [[ "$output" == *"role_arn = arn:aws:iam::111122223333:role/App"* ]]
}

@test "assume profile: unknown subcommand errors" {
  run "$ASSUME" profile bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"알 수 없는 profile 서브커맨드"* ]]
}
