#!/usr/bin/env bats

load helpers/stub

setup() {
  BINBOX_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  setup_stub_dir
  export XDG_CONFIG_HOME="$STUB_DIR/config"
  export XDG_STATE_HOME="$STUB_DIR/state"
}

teardown() {
  teardown_stub_dir
}

@test "tm projects --json: emits schema v1 and preserves spaces" {
  mkdir -p "$STUB_DIR/parent/alpha project" "$STUB_DIR/direct" "$XDG_CONFIG_HOME/tmux-sessionizer"
  printf '%s\n=%s\n' "$STUB_DIR/parent" "$STUB_DIR/direct" >"$XDG_CONFIG_HOME/tmux-sessionizer/dirs"

  run "$BINBOX_DIR/libexec/tm" projects --json
  [ "$status" -eq 0 ]
  run python3 -c '
import json, sys
p = json.loads(sys.argv[1])
assert p["schema_version"] == 1 and p["ok"] is True
assert sorted(x["path"] for x in p["data"]["projects"]) == sorted(sys.argv[2:])
' "$output" "$STUB_DIR/parent/alpha project" "$STUB_DIR/direct"
  [ "$status" -eq 0 ]
}

@test "tm sessions --json: emits typed session fields" {
  make_stub tmux '
case "$1" in
  list-sessions) printf "session-1\n" ;;
  display-message)
    case "${!#}" in
      "#{session_name}") printf "dev\n" ;;
      "#{session_windows}") printf "2\n" ;;
      "#{session_attached}") printf "1\n" ;;
      "#{session_created}") printf "123\n" ;;
    esac
    ;;
esac
'
  run "$BINBOX_DIR/libexec/tm" sessions --json
  [ "$status" -eq 0 ]
  run python3 -c '
import json, sys
s = json.loads(sys.argv[1])["data"]["sessions"][0]
assert s == {"id":"session-1","name":"dev","windows":2,"attached":True,"created_at_unix":123,"state_source":"tmux"}
' "$output"
  [ "$status" -eq 0 ]
}

@test "agents --json: marks legacy pane state as scrape" {
  make_stub tmux '
case "$1" in
  list-panes) printf "%%1\n" ;;
  capture-pane) printf "Working (esc to interrupt)\n› implement JSON\n" ;;
  display-message)
    case "${!#}" in
      "#{session_name}:#{window_index}.#{pane_index}") printf "dev:1.1\n" ;;
      "#{pane_current_command}") printf "codex\n" ;;
      "#{pane_current_path}") printf "/tmp/project path\n" ;;
      "#{pane_title}") printf "Codex task\n" ;;
      "#{pane_start_time}") printf "1\n" ;;
    esac
    ;;
esac
'
  make_stub wb '
printf "%s\n" "$@" >> "$STUB_DIR/wb.args"
exit 7
'
  run "$BINBOX_DIR/libexec/agents" --json
  [ "$status" -eq 0 ]
  run python3 -c '
import json, sys
a = json.loads(sys.argv[1])["data"]["agents"][0]
assert a["agent_kind"] == "codex"
assert a["state"] == "running"
assert a["state_source"] == "scrape"
assert a["path"] == "/tmp/project path"
' "$output"
  [ "$status" -eq 0 ]
  run python3 -c '
from pathlib import Path
args = Path(__import__("sys").argv[1]).read_text().splitlines()
assert args == ["compatibility", "observe", "--client", "binbox", "--feature", "agents", "--source", "scrape"]
' "$STUB_DIR/wb.args"
  [ "$status" -eq 0 ]
}

@test "doctor --json: stdout is one valid envelope" {
  run "$BINBOX_DIR/libexec/binbox-doctor" --json
  [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
  run python3 -c '
import json, sys
p = json.loads(sys.argv[1])
assert p["schema_version"] == 1
assert isinstance(p["data"]["capabilities"], list)
' "$output"
  [ "$status" -eq 0 ]
}
