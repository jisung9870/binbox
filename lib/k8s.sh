#!/usr/bin/env bash
# lib/k8s.sh — klog/kexec/kpf 공통 pod/컨테이너 선택 헬퍼
[[ -n "${_BINBOX_K8S_SH:-}" ]] && return 0
_BINBOX_K8S_SH=1

# die/fzf_pick 의존 (이중 source는 가드가 막는다)
# shellcheck source=common.sh
source "${BASH_SOURCE[0]%/*}/common.sh"

# k8s_pick_pod [NAMESPACE] — pod 목록에서 fzf로 선택, pod 이름을 stdout으로.
# 빈 NAMESPACE = 현재 namespace. 취소(Esc): 빈 출력 + 0. 목록 조회 실패: die.
k8s_pick_pod() {
  local ns="${1:-}" ns_args=() pods selected
  if [[ -n "$ns" ]]; then ns_args=(-n "$ns"); fi
  pods=$(kubectl get pods ${ns_args[@]+"${ns_args[@]}"} --no-headers 2>/dev/null || true)
  [[ -n "$pods" ]] || die "pod 목록을 가져올 수 없습니다."
  selected=$(printf '%s\n' "$pods" | fzf_pick \
    --prompt="pod 선택: " \
    --preview="kubectl describe pod ${ns_args[*]+${ns_args[*]}} {1} 2>/dev/null | tail -20" \
    --preview-window=down:12:wrap)
  [[ -n "$selected" ]] || return 0
  printf '%s\n' "$selected" | awk '{print $1}'
}

# k8s_pick_container [NAMESPACE] POD — 컨테이너 2개 이상이면 fzf로 선택해 이름을 stdout으로.
# 0~1개면 빈 출력 + 0 (컨테이너 인자 불필요). 취소(Esc): 종료코드 1 → 호출부 `|| exit 0`.
k8s_pick_container() {
  local ns="${1:-}" pod="$2" ns_args=() containers container
  if [[ -n "$ns" ]]; then ns_args=(-n "$ns"); fi
  containers=$(kubectl get pod "$pod" ${ns_args[@]+"${ns_args[@]}"} \
    -o jsonpath='{.spec.containers[*].name}' 2>/dev/null | tr ' ' '\n' || true)
  if [[ $(printf '%s\n' "$containers" | grep -c .) -gt 1 ]]; then
    container=$(printf '%s\n' "$containers" | fzf_pick --prompt="컨테이너 선택: ")
    [[ -n "$container" ]] || return 1
    printf '%s\n' "$container"
  fi
}
