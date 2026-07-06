#!/usr/bin/env bats
# tm (tmux 통합 명령) 테스트 — kill / dirs / go
# NOTE: bats가 멀티바이트 테스트명을 처리하지 못해 테스트명은 영문 사용

load helpers/stub

setup() {
  BINBOX_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  setup_stub_dir
  export XDG_CONFIG_HOME="$STUB_DIR/config"
  export XDG_STATE_HOME="$STUB_DIR/state"
  DIRS_FILE="$XDG_CONFIG_HOME/tmux-sessionizer/dirs"
}

teardown() {
  teardown_stub_dir
}

# --- 공통 ---

@test "tm -h: exits 0" {
  run "$BINBOX_DIR/libexec/tm" -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"사용법"* ]]
}

@test "tm: unknown subcommand errors" {
  run "$BINBOX_DIR/libexec/tm" bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"알 수 없는 서브커맨드"* ]]
}

# --- kill ---

@test "tm kill <pattern>: no matching sessions exits 0" {
  make_stub tmux 'if [[ "${1:-}" == "list-sessions" ]]; then printf "alpha\nbeta\n"; fi'
  run "$BINBOX_DIR/libexec/tm" kill zzz
  [ "$status" -eq 0 ]
  [[ "$output" == *"매칭되는 세션이 없습니다"* ]]
}

@test "tm kill <pattern>: y kills only matching sessions" {
  make_stub tmux "
case \"\${1:-}\" in
  list-sessions) printf 'dev-a\ndev-b\nprod\n' ;;
  kill-session) printf '%s\n' \"\$*\" >> '$STUB_DIR/tmux.calls' ;;
esac
"
  run bash -c "printf 'y' | '$BINBOX_DIR/libexec/tm' kill dev"
  [ "$status" -eq 0 ]
  grep -q 'kill-session -t dev-a' "$STUB_DIR/tmux.calls"
  grep -q 'kill-session -t dev-b' "$STUB_DIR/tmux.calls"
  ! grep -q 'prod' "$STUB_DIR/tmux.calls"
}

@test "tm kill <pattern>: n cancels without killing" {
  make_stub tmux "
case \"\${1:-}\" in
  list-sessions) printf 'dev-a\n' ;;
  kill-session) printf '%s\n' \"\$*\" >> '$STUB_DIR/tmux.calls' ;;
esac
"
  run bash -c "printf 'n' | '$BINBOX_DIR/libexec/tm' kill dev"
  [ "$status" -eq 0 ]
  [[ "$output" == *"취소됨"* ]]
  [ ! -f "$STUB_DIR/tmux.calls" ]
}

@test "tm kill: fzf multi-select kills chosen sessions" {
  make_stub tmux "
case \"\${1:-}\" in
  list-sessions) printf 'dev-a\ndev-b\n' ;;
  kill-session) printf '%s\n' \"\$*\" >> '$STUB_DIR/tmux.calls' ;;
esac
"
  make_stub fzf 'cat'
  run "$BINBOX_DIR/libexec/tm" kill
  [ "$status" -eq 0 ]
  grep -q 'kill-session -t dev-a' "$STUB_DIR/tmux.calls"
  grep -q 'kill-session -t dev-b' "$STUB_DIR/tmux.calls"
}

@test "tm kill: fzf cancel exits 0 without killing" {
  make_stub tmux 'if [[ "${1:-}" == "list-sessions" ]]; then printf "dev-a\n"; fi'
  make_stub fzf 'cat >/dev/null; exit 130'
  run "$BINBOX_DIR/libexec/tm" kill
  [ "$status" -eq 0 ]
  [[ "$output" == *"선택 취소"* ]]
  [ ! -f "$STUB_DIR/tmux.calls" ]
}

# --- dirs ---

@test "tm dirs add: creates config and appends path" {
  mkdir -p "$STUB_DIR/proj"
  run "$BINBOX_DIR/libexec/tm" dirs add "$STUB_DIR/proj"
  [ "$status" -eq 0 ]
  [[ "$output" == *"추가됨"* ]]
  grep -Fxq "$STUB_DIR/proj" "$DIRS_FILE"
}

@test "tm dirs add: duplicate entry is skipped" {
  mkdir -p "$STUB_DIR/proj"
  run "$BINBOX_DIR/libexec/tm" dirs add "$STUB_DIR/proj"
  run "$BINBOX_DIR/libexec/tm" dirs add "$STUB_DIR/proj"
  [ "$status" -eq 0 ]
  [[ "$output" == *"이미 등록"* ]]
  [ "$(grep -Fxc "$STUB_DIR/proj" "$DIRS_FILE")" -eq 1 ]
}

@test "tm dirs add -d: appends with = prefix" {
  mkdir -p "$STUB_DIR/solo"
  run "$BINBOX_DIR/libexec/tm" dirs add -d "$STUB_DIR/solo"
  [ "$status" -eq 0 ]
  grep -Fxq "=$STUB_DIR/solo" "$DIRS_FILE"
}

@test "tm dirs add: abbreviates HOME to tilde" {
  mkdir -p "$STUB_DIR/home/myproj"
  run env HOME="$STUB_DIR/home" "$BINBOX_DIR/libexec/tm" dirs add "$STUB_DIR/home/myproj"
  [ "$status" -eq 0 ]
  grep -Fxq '~/myproj' "$DIRS_FILE"
}

@test "tm dirs add: nonexistent path errors" {
  run "$BINBOX_DIR/libexec/tm" dirs add "$STUB_DIR/no-such-dir"
  [ "$status" -eq 1 ]
  [[ "$output" == *"디렉토리가 없습니다"* ]]
}

@test "tm dirs: lists parent, direct, and dead entries" {
  mkdir -p "$STUB_DIR/parent/child" "$STUB_DIR/solo" "$(dirname "$DIRS_FILE")"
  {
    echo "# comment"
    echo "$STUB_DIR/parent"
    echo "=$STUB_DIR/solo"
    echo "$STUB_DIR/ghost"
  } > "$DIRS_FILE"
  run "$BINBOX_DIR/libexec/tm" dirs
  [ "$status" -eq 0 ]
  [[ "$output" == *"부모  $STUB_DIR/parent (후보 1개)"* ]]
  [[ "$output" == *"직접  =$STUB_DIR/solo"* ]]
  [[ "$output" == *"없음! $STUB_DIR/ghost"* ]]
}

@test "tm dirs rm: removes selected lines, keeps comments" {
  mkdir -p "$(dirname "$DIRS_FILE")"
  {
    echo "# keep me"
    echo "$STUB_DIR/a"
    echo "=$STUB_DIR/b"
  } > "$DIRS_FILE"
  make_stub fzf 'cat'
  run "$BINBOX_DIR/libexec/tm" dirs rm
  [ "$status" -eq 0 ]
  [[ "$output" == *"제거됨"* ]]
  grep -Fxq "# keep me" "$DIRS_FILE"
  ! grep -q "$STUB_DIR/a" "$DIRS_FILE"
  ! grep -q "=$STUB_DIR/b" "$DIRS_FILE"
}

# --- go ---

@test "tm go: direct (=) entries appear as candidates" {
  mkdir -p "$STUB_DIR/parent/projA" "$STUB_DIR/solo" "$(dirname "$DIRS_FILE")"
  {
    echo "$STUB_DIR/parent"
    echo "=$STUB_DIR/solo"
  } > "$DIRS_FILE"
  make_stub tmux "printf '%s\n' \"\$*\" >> '$STUB_DIR/tmux.calls'"
  make_stub fzf "tee '$STUB_DIR/fzf.in' | awk 'NR==1'"
  make_stub pgrep 'exit 1'
  run env -u TMUX "$BINBOX_DIR/libexec/tm" go
  [ "$status" -eq 0 ]
  cut -f3 "$STUB_DIR/fzf.in" | grep -Fxq "$STUB_DIR/solo"
  cut -f3 "$STUB_DIR/fzf.in" | grep -Fxq "$STUB_DIR/parent/projA"
  grep -q "new-session -s projA -c $STUB_DIR/parent/projA" "$STUB_DIR/tmux.calls"
}

@test "tm go: fzf cancel exits 0 without session" {
  mkdir -p "$STUB_DIR/parent/projA" "$(dirname "$DIRS_FILE")"
  echo "$STUB_DIR/parent" > "$DIRS_FILE"
  make_stub tmux "printf '%s\n' \"\$*\" >> '$STUB_DIR/tmux.calls'"
  make_stub fzf 'cat >/dev/null; exit 130'
  make_stub pgrep 'exit 1'
  run env -u TMUX "$BINBOX_DIR/libexec/tm" go
  [ "$status" -eq 0 ]
  ! grep -q 'new-session' "$STUB_DIR/tmux.calls"
}

@test "tm go: marks projects that already have a session" {
  mkdir -p "$STUB_DIR/parent/projA" "$STUB_DIR/parent/projB" "$(dirname "$DIRS_FILE")"
  echo "$STUB_DIR/parent" > "$DIRS_FILE"
  make_stub tmux "
if [[ \"\${1:-}\" == list-sessions ]]; then printf 'projA\n'; fi
"
  make_stub fzf "tee '$STUB_DIR/fzf.in' >/dev/null; exit 130"
  make_stub pgrep 'exit 1'
  run env -u TMUX "$BINBOX_DIR/libexec/tm" go
  [ "$status" -eq 0 ]
  grep '^●' "$STUB_DIR/fzf.in" | grep -q projA
  ! { grep '^●' "$STUB_DIR/fzf.in" | grep -q projB; }
}

@test "tm go: displays HOME paths abbreviated with tilde" {
  mkdir -p "$STUB_DIR/home/parent/projA" "$(dirname "$DIRS_FILE")"
  echo "$STUB_DIR/home/parent" > "$DIRS_FILE"
  make_stub tmux "printf '%s\n' \"\$*\" >> '$STUB_DIR/tmux.calls'"
  make_stub fzf "tee '$STUB_DIR/fzf.in' >/dev/null; exit 130"
  make_stub pgrep 'exit 1'
  run env -u TMUX HOME="$STUB_DIR/home" "$BINBOX_DIR/libexec/tm" go
  [ "$status" -eq 0 ]
  cut -f2 "$STUB_DIR/fzf.in" | grep -Fxq '~/parent/projA'
}

@test "tm dirs prune: removes dead entries after confirm" {
  mkdir -p "$STUB_DIR/live" "$(dirname "$DIRS_FILE")"
  {
    echo "# comment"
    echo "$STUB_DIR/live"
    echo "$STUB_DIR/dead1"
    echo "=$STUB_DIR/dead2"
  } > "$DIRS_FILE"
  run bash -c "printf 'y' | '$BINBOX_DIR/libexec/tm' dirs prune"
  [ "$status" -eq 0 ]
  [[ "$output" == *"2개 제거됨"* ]]
  grep -Fxq "$STUB_DIR/live" "$DIRS_FILE"
  grep -Fxq "# comment" "$DIRS_FILE"
  ! grep -q dead1 "$DIRS_FILE"
  ! grep -q dead2 "$DIRS_FILE"
}

@test "tm dirs prune: nothing to prune exits 0" {
  mkdir -p "$STUB_DIR/live" "$(dirname "$DIRS_FILE")"
  echo "$STUB_DIR/live" > "$DIRS_FILE"
  run "$BINBOX_DIR/libexec/tm" dirs prune
  [ "$status" -eq 0 ]
  [[ "$output" == *"정리할 항목이 없습니다"* ]]
}
