# shell/init.zsh — binbox zsh 초기화. bb setup이 .zshrc에 source 라인을 추가한다.
# 이 파일은 repo에 있으므로 이후 변경은 bb upgrade만으로 반영된다 (rc 재수정 불필요).
# shellcheck 미지원 파일 (zsh 문법) — binbox-check가 검사하지 않는다.

[[ -n "${_BINBOX_INIT_ZSH:-}" ]] && return 0 # 이중 로드 가드
_BINBOX_INIT_ZSH=1

# ${(%):-%N} = 현재 source 중인 파일 경로 → shell/의 부모 = repo root
_binbox_dir="${${(%):-%N}:A:h:h}"

# 1) PATH — bb 심볼릭 링크 위치(~/.local/bin) 보장.
#    링크가 안 잡히는 환경(구형 macOS 등)은 repo를 직접 PATH에 추가.
typeset -gU path fpath # 중복 자동 제거
path=("$HOME/.local/bin" $path)
command -v bb >/dev/null 2>&1 || path=("$_binbox_dir" $path)

# 2) 자동완성 — compinit 실행 전이면 fpath 추가만으로 충분.
#    이미 실행됐으면(oh-my-zsh 등 — 이 블록이 rc 끝에 붙는 경우) compdef로 수동 등록.
fpath=("$_binbox_dir/completions" $fpath)
if (( $+functions[compdef] )); then
  autoload -Uz _bb _binbox
  compdef _bb bb
  # _binbox 1행(#compdef ...)에서 대상 명령 목록을 읽는다 (목록 이중 관리 방지)
  _binbox_line="$(head -n1 "$_binbox_dir/completions/_binbox" 2>/dev/null)"
  _binbox_svcs=(${=_binbox_line#\#compdef})
  (( ${#_binbox_svcs} )) && compdef _binbox "${(@)_binbox_svcs}"
  unset _binbox_line _binbox_svcs
fi

# 3) 개별 명령 alias 복원
source "$_binbox_dir/aliases.zsh"

# 4) raw terraform apply/destroy 실수 방지 guard
_binbox_terraform_guard_subcmd() {
  local arg skip_next=0
  for arg in "$@"; do
    if [[ "$skip_next" == 1 ]]; then
      skip_next=0
      continue
    fi
    case "$arg" in
      -chdir)
        skip_next=1
        ;;
      -chdir=*)
        ;;
      -*)
        ;;
      *)
        printf '%s\n' "$arg"
        return 0
        ;;
    esac
  done
  return 1
}

terraform() {
  if [[ "${BINBOX_TERRAFORM_GUARD:-1}" != "0" && "${BINBOX_ALLOW_RAW_TERRAFORM:-0}" != "1" ]]; then
    local _binbox_tf_subcmd
    _binbox_tf_subcmd="$(_binbox_terraform_guard_subcmd "$@")"
    case "$_binbox_tf_subcmd" in
      apply|destroy)
        {
          echo "✗ raw terraform $_binbox_tf_subcmd는 binbox guard가 막았습니다."
          echo "  사용: bb tfx session && bb tfx $_binbox_tf_subcmd"
          echo "  직접 실행: BINBOX_ALLOW_RAW_TERRAFORM=1 terraform $_binbox_tf_subcmd ..."
          echo "  guard 끄기: BINBOX_TERRAFORM_GUARD=0"
        } >&2
        return 2
        ;;
    esac
  fi
  command terraform "$@"
}

unset _binbox_dir
