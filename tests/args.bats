#!/usr/bin/env bats
# 인자 검증 / 도움말 / 에러 경로 테스트
# NOTE: bats가 멀티바이트 테스트명을 처리하지 못해 테스트명은 영문 사용

load helpers/stub

setup() {
  BINBOX_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  setup_stub_dir
}

teardown() {
  teardown_stub_dir
}

# --- portcheck ---

@test "portcheck: no args prints usage and exits 1" {
  run "$BINBOX_DIR/portcheck"
  [ "$status" -eq 1 ]
  [[ "$output" == *"사용법"* ]]
}

@test "portcheck: out-of-range port errors" {
  run "$BINBOX_DIR/portcheck" 99999
  [ "$status" -eq 1 ]
  [[ "$output" == *"올바른 포트 번호가 아닙니다"* ]]
}

@test "portcheck: non-numeric port errors" {
  run "$BINBOX_DIR/portcheck" abc
  [ "$status" -eq 1 ]
}

@test "portcheck: unknown option errors" {
  run "$BINBOX_DIR/portcheck" 8080 --bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"알 수 없는 옵션"* ]]
}

# --- dx ---

@test "dx: no args prints usage and exits 1" {
  run "$BINBOX_DIR/dx"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage"* ]]
}

@test "dx --help: exits 0" {
  run "$BINBOX_DIR/dx" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Available tools"* ]]
}

@test "dx --list: prints tool list" {
  run "$BINBOX_DIR/dx" --list
  [ "$status" -eq 0 ]
  [[ "$output" == *"ansible"* ]]
  [[ "$output" == *"ubuntu"* ]]
}

@test "dx: unknown tool errors" {
  make_stub docker 'exit 0'
  run "$BINBOX_DIR/dx" no-such-tool-xyz
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown tool"* ]]
}

# --- gitroot ---

@test "gitroot: prints repo root inside a git repo" {
  repo=$(mktemp -d)
  git -C "$repo" init -q
  mkdir -p "$repo/sub/dir"
  run bash -c "cd '$repo/sub/dir' && '$BINBOX_DIR/gitroot'"
  [ "$status" -eq 0 ]
  # macOS 심볼릭 링크(/tmp → /private/tmp) 대응: basename만 비교
  [[ "$output" == *"$(basename "$repo")" ]]
  rm -rf "$repo"
}

@test "gitroot --cd: prints eval-able cd command" {
  repo=$(mktemp -d)
  git -C "$repo" init -q
  run bash -c "cd '$repo' && '$BINBOX_DIR/gitroot' --cd"
  [ "$status" -eq 0 ]
  [[ "$output" == cd\ * ]]
  rm -rf "$repo"
}

@test "gitroot: errors outside a git repo" {
  dir=$(mktemp -d)
  run bash -c "cd '$dir' && GIT_CEILING_DIRECTORIES='$dir' '$BINBOX_DIR/gitroot'"
  [ "$status" -eq 1 ]
  rm -rf "$dir"
}

@test "gitroot -h: prints usage" {
  run "$BINBOX_DIR/gitroot" -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"사용법"* ]]
}

# --- md2jira ---

@test "md2jira: missing MD2JIRA_HOME gives friendly error" {
  run env MD2JIRA_HOME=/nonexistent-xyz "$BINBOX_DIR/md2jira" input.md
  [ "$status" -eq 1 ]
  [[ "$output" == *"MD2JIRA_HOME"* ]]
}

# --- tmux ---

@test "tmux-sessionizer/tmux-layout/tmux-kill-pattern -h: exit 0" {
  run "$BINBOX_DIR/tmux-sessionizer" -h
  [ "$status" -eq 0 ]
  run "$BINBOX_DIR/tmux-layout" -h
  [ "$status" -eq 0 ]
  run "$BINBOX_DIR/tmux-kill-pattern" -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"사용법"* ]]
}

@test "tmux-kill-pattern: no args prints usage and exits 1" {
  run "$BINBOX_DIR/tmux-kill-pattern"
  [ "$status" -eq 1 ]
  [[ "$output" == *"사용법"* ]]
}

@test "tmux-kill-pattern: no matching sessions exits 0" {
  make_stub tmux 'if [[ "${1:-}" == "list-sessions" ]]; then printf "alpha\nbeta\n"; fi'
  run "$BINBOX_DIR/tmux-kill-pattern" zzz
  [ "$status" -eq 0 ]
  [[ "$output" == *"매칭되는 세션이 없습니다"* ]]
}

@test "tmux-kill-pattern: y kills only matching sessions" {
  make_stub tmux "
case \"\${1:-}\" in
  list-sessions) printf 'dev-a\ndev-b\nprod\n' ;;
  kill-session) printf '%s\n' \"\$*\" >> '$STUB_DIR/tmux.calls' ;;
esac
"
  run bash -c "printf 'y' | '$BINBOX_DIR/tmux-kill-pattern' dev"
  [ "$status" -eq 0 ]
  grep -q 'kill-session -t dev-a' "$STUB_DIR/tmux.calls"
  grep -q 'kill-session -t dev-b' "$STUB_DIR/tmux.calls"
  ! grep -q 'prod' "$STUB_DIR/tmux.calls"
}

@test "tmux-kill-pattern: n cancels without killing" {
  make_stub tmux "
case \"\${1:-}\" in
  list-sessions) printf 'dev-a\n' ;;
  kill-session) printf '%s\n' \"\$*\" >> '$STUB_DIR/tmux.calls' ;;
esac
"
  run bash -c "printf 'n' | '$BINBOX_DIR/tmux-kill-pattern' dev"
  [ "$status" -eq 0 ]
  [[ "$output" == *"취소됨"* ]]
  [ ! -f "$STUB_DIR/tmux.calls" ]
}

# --- help paths ---

@test "kctx/kns/tmux-attach -h: exit 0" {
  run "$BINBOX_DIR/kctx" -h
  [ "$status" -eq 0 ]
  run "$BINBOX_DIR/kns" -h
  [ "$status" -eq 0 ]
  run "$BINBOX_DIR/tmux-attach" -h
  [ "$status" -eq 0 ]
}
