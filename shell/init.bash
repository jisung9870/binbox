# shell/init.bash — binbox bash 초기화 (WSL/Linux 등). bb setup이 .bashrc에 source 라인을 추가한다.
# 이 파일은 repo에 있으므로 이후 변경은 bb upgrade만으로 반영된다 (rc 재수정 불필요).

[ -n "${_BINBOX_INIT_BASH:-}" ] && return 0 # 이중 로드 가드
_BINBOX_INIT_BASH=1

_binbox_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

# 1) PATH — bb 심볼릭 링크 위치(~/.local/bin) 보장, 미해석 시 repo 직접 추가
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) PATH="$HOME/.local/bin:$PATH" ;;
esac
command -v bb >/dev/null 2>&1 || PATH="$_binbox_dir:$PATH"
export PATH

# 2) 개별 명령 alias 복원 (aliases.zsh의 bash 버전 — 실행 비트만 검사)
for _t in "$_binbox_dir"/libexec/*; do
  [ -f "$_t" ] && [ -x "$_t" ] || continue
  _name=${_t##*/}
  # shellcheck disable=SC2139 # 정의 시점 확장이 의도된 동작 (도구별 alias)
  case "$_name" in
    awsp|wenv) ;; # 아래에서 eval 래핑 함수로 정의
    *) alias "$_name"="bb $_name" ;;
  esac
done
unset _t _name

# awsp/wenv는 부모 셸의 환경변수를 바꿔야 하므로 eval 래핑
awsp() { eval "$(bb awsp "$@")"; }
wenv() { eval "$(bb wenv "$@")"; }

# 3) bb 자동완성 (완성 시점에 bb list 호출 — 도구 추가 자동 반영)
_bb_complete() {
  local cur=${COMP_WORDS[COMP_CWORD]}
  if [ "$COMP_CWORD" -eq 1 ]; then
    # shellcheck disable=SC2207
    COMPREPLY=( $(compgen -W "list help new upgrade doctor check setup $(bb list 2>/dev/null)" -- "$cur") )
  elif [ "$COMP_CWORD" -eq 2 ] && [ "${COMP_WORDS[1]}" = help ]; then
    # shellcheck disable=SC2207
    COMPREPLY=( $(compgen -W "$(bb list 2>/dev/null)" -- "$cur") )
  fi
}
complete -F _bb_complete bb

unset _binbox_dir
