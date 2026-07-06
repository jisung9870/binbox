#!/usr/bin/env bash
# bb — binbox 통합 진입점 (busybox 스타일 디스패처)
# 도구 실체는 libexec/에 있고 PATH에는 bb만 노출된다.
# 개별 명령어는 aliases.zsh를 source하면 alias로 복원된다.
set -euo pipefail

_self=$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")
BINBOX_DIR=$(cd "$(dirname "$_self")" && pwd)
# shellcheck source=lib/common.sh
source "$BINBOX_DIR/lib/common.sh" || { echo "lib/common.sh not found" >&2; exit 1; }

usage() {
  cat <<'EOF'
bb — binbox 통합 진입점

사용법:
  bb <tool> [args...]   도구 실행 (예: bb kctx, bb klog -n mon)
  bb list               도구 목록
  bb help [tool]        전체/도구별 도움말
  bb doctor             의존성 점검 (= binbox-doctor)
  bb check              shellcheck 일괄 실행 (= binbox-check)
  bb new <name>         템플릿이 채워진 새 도구 생성 (libexec/<name>)
  bb upgrade            binbox 업데이트 (git pull)

zsh 자동완성: .zshrc에 fpath=(~/binbox/completions $fpath) 추가 (compinit 전)
개별 명령 복원: .zshrc에 source ~/binbox/aliases.zsh 추가 (tm, kctx 등 alias)
EOF
}

list_tools() {
  local file name
  while IFS= read -r file; do
    head -1 "$file" 2>/dev/null | grep -q '^#!/usr/bin/env bash' || continue
    [[ -x "$file" ]] || continue
    name=$(basename "$file")
    printf '%s\n' "$name"
  done < <(find "$BINBOX_DIR/libexec" -maxdepth 1 -type f -print 2>/dev/null | sort)
}

resolve_tool() {
  # 예약어 별칭 + 경로 조작 차단
  local tool="$1"
  case "$tool" in
    doctor) tool="binbox-doctor" ;;
    check) tool="binbox-check" ;;
  esac
  [[ "$tool" == */* ]] && die "올바르지 않은 도구 이름: $tool"
  if [[ ! -x "$BINBOX_DIR/libexec/$tool" ]] ||
    ! head -1 "$BINBOX_DIR/libexec/$tool" 2>/dev/null | grep -q '^#!/usr/bin/env bash'; then
    {
      echo "알 수 없는 도구: $tool"
      echo
      echo "사용 가능한 도구:"
      list_tools
    } >&2
    exit 1
  fi
  printf '%s' "$tool"
}

do_upgrade() {
  need_cmd git
  local before after
  before=$(git -C "$BINBOX_DIR" rev-parse HEAD 2>/dev/null) ||
    die "git 저장소가 아닙니다: $BINBOX_DIR"
  git -C "$BINBOX_DIR" pull --ff-only ||
    die "업데이트 실패. 로컬 변경이 있으면 커밋/스태시 후 다시 시도하세요."
  after=$(git -C "$BINBOX_DIR" rev-parse HEAD)
  if [[ "$before" == "$after" ]]; then
    echo "이미 최신입니다."
  else
    echo
    echo "업데이트된 변경 사항:"
    git -C "$BINBOX_DIR" log --oneline "${before}..${after}"
  fi
}

case "${1:-}" in
  ""|-h|--help)
    usage
    echo
    echo "사용 가능한 도구:"
    list_tools
    exit 0
    ;;
  list)
    list_tools
    exit 0
    ;;
  help)
    if [[ -z "${2:-}" ]]; then
      usage
      echo
      echo "사용 가능한 도구:"
      list_tools
      exit 0
    fi
    tool=$(resolve_tool "$2")
    exec "$BINBOX_DIR/libexec/$tool" -h
    ;;
  new)
    [[ -n "${2:-}" ]] || die "사용법: bb new <name>"
    new_tool="$2"
    [[ "$new_tool" =~ ^[a-z][a-z0-9-]*$ ]] || die "도구 이름은 소문자로 시작, 소문자/숫자/하이픈만 가능합니다: $new_tool"
    case "$new_tool" in
      list|help|doctor|check|upgrade|new) die "bb 예약어라 사용할 수 없습니다: $new_tool" ;;
    esac
    target="$BINBOX_DIR/libexec/$new_tool"
    [[ -e "$target" ]] && die "이미 존재합니다: $target"
    cat >"$target" <<TEMPLATE
#!/usr/bin/env bash
# ${new_tool} — TODO: 한 줄 설명
set -euo pipefail

_self=\$(readlink -f "\${BASH_SOURCE[0]}" 2>/dev/null || echo "\${BASH_SOURCE[0]}")
BINBOX_DIR=\$(cd "\$(dirname "\$_self")/.." && pwd)
# shellcheck source=../lib/common.sh
source "\$BINBOX_DIR/lib/common.sh" || { echo "lib/common.sh not found" >&2; exit 1; }

usage() {
  cat <<'EOF'
${new_tool} — TODO: 설명

사용법:
  ${new_tool} [옵션]
EOF
}

case "\${1:-}" in
  -h|--help|help) usage; exit 0 ;;
esac

die "TODO: 구현"
TEMPLATE
    chmod +x "$target"
    echo "✓ 생성됨: $target"
    echo "  bb list / shellcheck / zsh 완성에 자동 반영됩니다. (alias는 새 셸부터)"
    exit 0
    ;;
  upgrade)
    do_upgrade
    exit 0
    ;;
  *)
    tool=$(resolve_tool "$1")
    shift
    # exec: TTY/fzf 인터랙티브, 종료코드, eval "$(bb awsp)" 모두 보존
    exec "$BINBOX_DIR/libexec/$tool" "$@"
    ;;
esac
