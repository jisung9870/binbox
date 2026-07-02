#!/usr/bin/env bash
# lib/common.sh — binbox 공통 함수. 각 스크립트가 source해서 사용한다.
[[ -n "${_BINBOX_COMMON_SH:-}" ]] && return 0
_BINBOX_COMMON_SH=1

# die MSG... — stderr로 출력 후 종료
die() {
  printf '%s\n' "$@" >&2
  exit 1
}

# need_cmd CMD [힌트] — 명령어 존재 확인, 없으면 die
need_cmd() {
  local cmd="$1" hint="${2:-}"
  command -v "$cmd" >/dev/null 2>&1 && return 0
  if [[ -n "$hint" ]]; then
    die "${cmd}가 설치되지 않았습니다. ($hint)"
  else
    die "${cmd}가 설치되지 않았습니다."
  fi
}

# fzf_pick [fzf args...] — stdin 목록에서 fzf 선택.
# 취소(Esc) 시 빈 출력 + 종료코드 0 (set -e에서 안전)
fzf_pick() {
  fzf "$@" || true
}

# confirm PROMPT — y/Y면 0 반환
confirm() {
  local reply
  read -r -p "$1 (y/n) " -n 1 reply
  echo >&2
  [[ $reply =~ ^[Yy]$ ]]
}

# sanitize_session NAME — tmux 세션명에 쓸 수 없는 문자 치환
sanitize_session() {
  printf '%s' "$1" | tr '.:' '__'
}
