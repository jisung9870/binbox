# aliases.zsh — bb 일원화 후 개별 명령 복원
# .zshrc에 추가: source ~/binbox/aliases.zsh  (PATH에는 bb만 있으면 됨)
# 특정 명령이 필요 없으면 이 파일 대신 개별 alias만 등록해도 된다.

_binbox_root="${0:A:h}"

# libexec의 모든 실행 파일을 alias로 복원 (bb new로 추가한 도구도 자동 반영)
for _t in "$_binbox_root"/libexec/*(N.x:t); do
  case "$_t" in
    awsp|wenv) ;; # 아래에서 eval 래핑 함수로 정의
    *) alias "$_t"="bb $_t" ;;
  esac
done
unset _t

# awsp/wenv는 부모 셸의 환경변수를 바꿔야 하므로 eval 래핑
awsp() { eval "$(bb awsp "$@")"; }
wenv() { eval "$(bb wenv "$@")"; }

unset _binbox_root
