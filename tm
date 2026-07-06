#!/usr/bin/env bash
# tm — tmux 세션 관리 통합 명령 (go / attach / layout / kill)
# 구 tmux-sessionizer / tmux-attach / tmux-layout / tmux-kill-sessions / tmux-kill-pattern 통합
set -euo pipefail

_self=$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")
BINBOX_DIR=$(cd "$(dirname "$_self")" && pwd)
# shellcheck source=lib/common.sh
source "$BINBOX_DIR/lib/common.sh" || { echo "lib/common.sh not found" >&2; exit 1; }

# 설정/상태 경로는 구 tmux-sessionizer 시절 그대로 유지 —
# nvim(editor.lua)이 dirs 파일을 직접 파싱하므로 위치/포맷 변경 금지 (ROADMAP 외부 결합 지점)
CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/tmux-sessionizer/dirs"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/tmux-sessionizer"
RECENT_FILE="$STATE_DIR/recent"
LAYOUT_DIR="$BINBOX_DIR/tmux-layouts"

usage() {
  cat <<'EOF'
tm — tmux 세션 관리 통합 명령

사용법:
  tm                      # = tm go
  tm go                   # 프로젝트 디렉토리 선택 → 세션 생성/전환 (최근 항목 우선)
  tm attach               # 기존 세션 선택 또는 새 세션 생성 (tmux 안이면 전환)
  tm layout [이름] [경로]  # 레이아웃 선택 후 세션 생성 (golang, k8s, terraform)
  tm kill                 # fzf 다중 선택으로 세션 삭제
  tm kill <패턴>           # 패턴 매칭 세션 일괄 삭제 (확인 후)

설정:
  프로젝트 목록: ~/.config/tmux-sessionizer/dirs (한 줄에 하나, ~ 사용 가능)
  최근 기록:     ~/.local/state/tmux-sessionizer/recent
EOF
}

# --- go (구 tmux-sessionizer) ---

_go_read_candidates() {
  find "${valid_dirs[@]}" -mindepth 1 -maxdepth 1 -type d ! -name '.*' -print 2>/dev/null | sort -u
}

_go_ordered_candidates() {
  local candidates
  candidates=$(_go_read_candidates)
  [[ -n "$candidates" ]] || return 0

  if [[ -f "$RECENT_FILE" ]]; then
    while IFS= read -r recent; do
      [[ -n "$recent" ]] || continue
      if printf '%s\n' "$candidates" | grep -Fxq "$recent"; then
        printf '%s\n' "$recent"
      fi
    done <"$RECENT_FILE"
  fi

  printf '%s\n' "$candidates" | while IFS= read -r candidate; do
    if [[ -f "$RECENT_FILE" ]] && grep -Fxq "$candidate" "$RECENT_FILE"; then
      continue
    fi
    printf '%s\n' "$candidate"
  done
}

_go_record_recent() {
  local selected_path="$1"
  mkdir -p "$STATE_DIR"
  {
    printf '%s\n' "$selected_path"
    if [[ -f "$RECENT_FILE" ]]; then
      { grep -Fxv "$selected_path" "$RECENT_FILE" || true; } | while IFS= read -r recent; do
        [[ -d "$recent" ]] && printf '%s\n' "$recent"
      done
    fi
  } | awk 'NF && !seen[$0]++ {print}' | head -50 >"${RECENT_FILE}.tmp"
  mv "${RECENT_FILE}.tmp" "$RECENT_FILE"
}

cmd_go() {
  if [[ -f "$CONFIG_FILE" ]]; then
    PROJECT_DIRS=()
    while IFS= read -r line; do
      [[ -z "$line" || "$line" == \#* ]] && continue
      line="${line/#\~/$HOME}"
      PROJECT_DIRS+=("$line")
    done <"$CONFIG_FILE"
  else
    PROJECT_DIRS=("$HOME/home/projects" "$HOME/home/work")
  fi

  if [[ ${#PROJECT_DIRS[@]} -eq 0 ]]; then
    die "프로젝트 디렉토리가 설정되어 있지 않습니다: $CONFIG_FILE"
  fi

  valid_dirs=()
  for dir in "${PROJECT_DIRS[@]}"; do
    if [[ -d "$dir" ]]; then
      valid_dirs+=("$dir")
    fi
  done

  if [[ ${#valid_dirs[@]} -eq 0 ]]; then
    die "사용 가능한 프로젝트 디렉토리가 없습니다." "설정 파일을 확인하세요: $CONFIG_FILE"
  fi

  local candidates selected selected_name tmux_running
  candidates=$(_go_ordered_candidates)
  if [[ -z "$candidates" ]]; then
    die "선택할 프로젝트가 없습니다. 프로젝트 디렉토리에 하위 디렉토리를 추가하세요."
  fi

  selected=$(printf '%s\n' "$candidates" | fzf_pick --prompt="프로젝트 선택: ")

  if [[ -z "$selected" ]]; then
    return 0
  fi

  _go_record_recent "$selected"

  selected_name=$(sanitize_session "$(basename "$selected")")

  tmux_running=$(pgrep tmux || true)

  if [[ -z ${TMUX:-} ]] && [[ -z $tmux_running ]]; then
    tmux new-session -s "$selected_name" -c "$selected"
    return 0
  fi

  if ! tmux has-session -t="$selected_name" 2>/dev/null; then
    tmux new-session -ds "$selected_name" -c "$selected"
  fi

  if [[ -n ${TMUX:-} ]]; then
    tmux switch-client -t "$selected_name"
  else
    tmux attach-session -t "$selected_name"
  fi
}

# --- attach (구 tmux-attach) ---

cmd_attach() {
  local sessions session_name current_session other_sessions selected all_options
  sessions=$(tmux list-sessions -F "#{session_name}" 2>/dev/null || true)

  # 세션이 없으면 새로 생성
  if [[ -z "$sessions" ]]; then
    echo "실행 중인 tmux 세션이 없습니다."
    read -r -p "새 세션 이름 (Enter=default): " session_name
    session_name=${session_name:-default}
    tmux new-session -s "$session_name"
    return 0
  fi

  # 이미 tmux 안에 있으면
  if [[ -n "${TMUX:-}" ]]; then
    current_session=$(tmux display-message -p '#S')

    other_sessions=$(printf '%s\n' "$sessions" | grep -v "^${current_session}$" || true)

    if [[ -z "$other_sessions" ]]; then
      echo "현재 세션만 있습니다: $current_session"
      return 0
    fi

    selected=$(printf '%s\n' "$other_sessions" | fzf_pick --prompt="전환할 세션 선택: ")

    if [[ -n "$selected" ]]; then
      tmux switch-client -t "$selected"
    fi
  else
    # tmux 밖에 있으면 attach (새 세션 옵션 포함)
    all_options=$(printf "%s\n+ 새 세션 생성" "$sessions")

    selected=$(printf '%s\n' "$all_options" | fzf_pick --prompt="연결할 세션 선택: ")

    if [[ -z "$selected" ]]; then
      return 0
    fi

    if [[ "$selected" == "+ 새 세션 생성" ]]; then
      read -r -p "새 세션 이름: " session_name
      if [[ -n "$session_name" ]]; then
        tmux new-session -s "$session_name"
      fi
    else
      tmux attach-session -t "$selected"
    fi
  fi
}

# --- layout (구 tmux-layout) ---

cmd_layout() {
  local session_name="${1:-}" project_dir="${2:-$PWD}" layouts selected

  if [[ ! -d "$LAYOUT_DIR" ]]; then
    die "레이아웃 디렉토리가 없습니다: $LAYOUT_DIR"
  fi

  layouts=$(find "$LAYOUT_DIR" -maxdepth 1 -type f -name '*-layout' -perm -111 -print 2>/dev/null | sed 's#.*/##; s/-layout$//' | sort)

  if [[ -z "$layouts" ]]; then
    die "사용 가능한 레이아웃이 없습니다."
  fi

  selected=$(printf '%s\n' "$layouts" | fzf_pick --prompt="레이아웃 선택: ")

  if [[ -z "$selected" ]]; then
    return 0
  fi

  # 세션 이름이 없으면 입력 받기
  if [[ -z "$session_name" ]]; then
    read -r -p "세션 이름: " session_name
    if [[ -z "$session_name" ]]; then
      session_name="${selected}-$(date +%H%M)"
    fi
  fi

  if [[ ! -d "$project_dir" ]]; then
    die "프로젝트 디렉토리가 없습니다: $project_dir"
  fi

  exec "$LAYOUT_DIR/${selected}-layout" "$session_name" "$project_dir"
}

# --- kill (구 tmux-kill-sessions + tmux-kill-pattern) ---

cmd_kill() {
  local pattern="${1:-}" sessions to_kill

  if [[ -n "$pattern" ]]; then
    sessions=$(tmux list-sessions -F "#{session_name}" 2>/dev/null | grep -F "$pattern" || true)

    if [[ -z "$sessions" ]]; then
      echo "패턴 '$pattern'에 매칭되는 세션이 없습니다."
      return 0
    fi

    echo "다음 세션들을 제거합니다:"
    echo "$sessions"
    echo ""

    if ! confirm "계속하시겠습니까?"; then
      echo "취소됨"
      return 0
    fi
    to_kill="$sessions"
  else
    need_cmd fzf "brew install fzf"
    sessions=$(tmux list-sessions -F "#{session_name}" 2>/dev/null || true)

    if [[ -z "$sessions" ]]; then
      echo "실행 중인 세션이 없습니다."
      return 0
    fi

    to_kill=$(printf '%s\n' "$sessions" | fzf_pick --multi --prompt="삭제할 세션 선택 (Tab으로 다중 선택): ")

    if [[ -z "$to_kill" ]]; then
      echo "선택 취소"
      return 0
    fi
  fi

  printf '%s\n' "$to_kill" | while read -r session; do
    tmux kill-session -t "$session"
    echo "✓ $session 제거됨"
  done
}

sub="${1:-go}"
[[ $# -gt 0 ]] && shift || true

case "$sub" in
  -h|--help|help) usage; exit 0 ;;
  go)       need_cmd tmux "brew install tmux"; need_cmd fzf "brew install fzf"; cmd_go ;;
  attach|a) need_cmd tmux "brew install tmux"; need_cmd fzf "brew install fzf"; cmd_attach ;;
  layout)   need_cmd tmux "brew install tmux"; need_cmd fzf "brew install fzf"; cmd_layout "$@" ;;
  kill)     need_cmd tmux "brew install tmux"; cmd_kill "$@" ;;
  *) usage >&2; die "알 수 없는 서브커맨드: $sub" ;;
esac
