# aliases.zsh — bb 일원화 후 개별 명령 복원
# .zshrc에 추가: source ~/binbox/aliases.zsh  (PATH에는 bb만 있으면 됨)
# 특정 명령이 필요 없으면 이 파일 대신 개별 alias만 등록해도 된다.

_binbox_root="${0:A:h}"

# libexec의 모든 실행 파일을 alias로 복원 (bb new로 추가한 도구도 자동 반영)
for _t in "$_binbox_root"/libexec/*(N.x:t); do
  case "$_t" in
    assume) ;; # bb assume만 제공한다 (bare assume은 Granted 등 외부 명령과 충돌 가능)
    *) alias "$_t"="bb $_t" ;;
  esac
done
unset _t

# 환경변수를 바꾸는 도구(wenv/assume)는 자식 프로세스로 실행하면 부모 셸에 적용되지 않는다.
# bb를 함수로 감싸 이 도구만 현재 셸에서 eval → 'bb wenv'와 'bb assume'이 env를 적용한다.
# 새 env 변경 도구를 추가하면 아래 case에 " 이름 " 을 넣는다.
bb() {
  case " ${1:-} " in
    " wenv ")
      local _bb_env_output _bb_env_status
      _bb_env_output=$(command bb "$@")
      _bb_env_status=$?
      [[ $_bb_env_status -eq 0 ]] || return "$_bb_env_status"
      eval "$_bb_env_output"
      ;;
    " assume ")
      case " ${2:-} " in
        " list "|" current "|" exec "|" help "|" -h "|" --help ")
          command bb "$@"
          ;;
        *)
          local _bb_env_output _bb_env_status
          _bb_env_output=$(command bb "$@")
          _bb_env_status=$?
          [[ $_bb_env_status -eq 0 ]] || return "$_bb_env_status"
          eval "$_bb_env_output"
          ;;
      esac
      ;;
    *) command bb "$@" ;;
  esac
}

unset _binbox_root
