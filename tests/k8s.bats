#!/usr/bin/env bats
# klog/kexec/kpf 동작 고정(e2e) 테스트 — lib/k8s.sh 리팩터의 안전망
# NOTE: bats가 멀티바이트 테스트명을 처리하지 못해 테스트명은 영문 사용

load helpers/stub

setup() {
  BINBOX_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  setup_stub_dir
}

teardown() {
  teardown_stub_dir
}

# kubectl 스텁: 호출 인자("$*")를 kubectl.calls에 한 줄씩 기록하고 응답을 흉내낸다
# stub_kubectl [컨테이너들] [containerPort들] — 공백 구분
stub_kubectl() {
  local containers="${1:-app}" ports="${2:-}"
  make_stub kubectl "
printf '%s\n' \"\$*\" >> '$STUB_DIR/kubectl.calls'
case \"\$*\" in
  *'containers[*].name'*) printf '%s' '$containers' ;;
  *containerPort*) printf '%s' '$ports' ;;
  *'get pods'*) printf 'pod-a 1/1 Running 0 5m\npod-b 1/1 Running 0 3m\n' ;;
esac
exit 0
"
}

# fzf 스텁: 첫 항목 선택 (stdin 전체를 소비해 SIGPIPE 방지)
stub_fzf_pick_first() {
  make_stub fzf "awk 'NR==1'"
}

# fzf 스텁: Esc 취소
stub_fzf_cancel() {
  make_stub fzf 'cat >/dev/null; exit 130'
}

# --- klog ---

@test "klog <pod>: single container follows logs without fzf selection" {
  stub_kubectl "app"
  stub_fzf_pick_first
  run "$BINBOX_DIR/libexec/klog" my-pod
  [ "$status" -eq 0 ]
  grep -q 'logs -f --tail=200 my-pod' "$STUB_DIR/kubectl.calls"
}

@test "klog -n <ns> <pod>: passes namespace to every kubectl call" {
  stub_kubectl "app"
  stub_fzf_pick_first
  run "$BINBOX_DIR/libexec/klog" -n myns my-pod
  [ "$status" -eq 0 ]
  grep -q 'get pod my-pod -n myns' "$STUB_DIR/kubectl.calls"
  grep -q 'logs -f --tail=200 -n myns my-pod' "$STUB_DIR/kubectl.calls"
}

@test "klog --tail <N>: overrides tail count" {
  stub_kubectl "app"
  stub_fzf_pick_first
  run "$BINBOX_DIR/libexec/klog" --tail 500 my-pod
  [ "$status" -eq 0 ]
  grep -q 'logs -f --tail=500 my-pod' "$STUB_DIR/kubectl.calls"
}

@test "klog: no args picks pod via fzf then follows logs" {
  stub_kubectl "app"
  stub_fzf_pick_first
  run "$BINBOX_DIR/libexec/klog"
  [ "$status" -eq 0 ]
  grep -q 'get pods --no-headers' "$STUB_DIR/kubectl.calls"
  grep -q 'logs -f --tail=200 pod-a' "$STUB_DIR/kubectl.calls"
}

@test "klog: cancel at pod selection exits 0 without logs call" {
  stub_kubectl "app"
  stub_fzf_cancel
  run "$BINBOX_DIR/libexec/klog"
  [ "$status" -eq 0 ]
  ! grep -q '^logs' "$STUB_DIR/kubectl.calls"
}

@test "klog <pod>: multi-container picks container via fzf" {
  stub_kubectl "app sidecar"
  stub_fzf_pick_first
  run "$BINBOX_DIR/libexec/klog" my-pod
  [ "$status" -eq 0 ]
  grep -q 'logs -f --tail=200 my-pod -c app' "$STUB_DIR/kubectl.calls"
}

# --- kexec ---

@test "kexec <pod>: single container execs shell" {
  stub_kubectl "app"
  stub_fzf_pick_first
  run "$BINBOX_DIR/libexec/kexec" my-pod
  [ "$status" -eq 0 ]
  grep -q 'exec -it my-pod' "$STUB_DIR/kubectl.calls"
}

@test "kexec <pod>: multi-container passes -c with picked container" {
  stub_kubectl "app sidecar"
  stub_fzf_pick_first
  run "$BINBOX_DIR/libexec/kexec" my-pod
  [ "$status" -eq 0 ]
  grep -q 'exec -it my-pod -c app' "$STUB_DIR/kubectl.calls"
}

@test "kexec <pod>: cancel at container selection exits 0 without exec call" {
  stub_kubectl "app sidecar"
  stub_fzf_cancel
  run "$BINBOX_DIR/libexec/kexec" my-pod
  [ "$status" -eq 0 ]
  ! grep -q '^exec' "$STUB_DIR/kubectl.calls"
}

# --- kpf ---

@test "kpf <pod> <local:remote>: forwards given ports" {
  stub_kubectl "app"
  stub_fzf_pick_first
  run "$BINBOX_DIR/libexec/kpf" my-pod 9000:8080
  [ "$status" -eq 0 ]
  [[ "$output" == *"localhost:9000"* ]]
  grep -q 'port-forward my-pod 9000:8080' "$STUB_DIR/kubectl.calls"
}

@test "kpf <pod> <port>: expands single port to local:remote" {
  stub_kubectl "app"
  stub_fzf_pick_first
  run "$BINBOX_DIR/libexec/kpf" my-pod 8080
  [ "$status" -eq 0 ]
  grep -q 'port-forward my-pod 8080:8080' "$STUB_DIR/kubectl.calls"
}

@test "kpf <pod>: auto-detects single declared containerPort" {
  stub_kubectl "app" "8080"
  stub_fzf_pick_first
  run "$BINBOX_DIR/libexec/kpf" my-pod
  [ "$status" -eq 0 ]
  grep -q 'port-forward my-pod 8080:8080' "$STUB_DIR/kubectl.calls"
}

@test "kpf <pod>: multiple declared ports picks one via fzf" {
  stub_kubectl "app" "8080 9090"
  stub_fzf_pick_first
  run "$BINBOX_DIR/libexec/kpf" my-pod
  [ "$status" -eq 0 ]
  grep -q 'port-forward my-pod 8080:8080' "$STUB_DIR/kubectl.calls"
}

# --- lib/k8s.sh 단위 테스트 ---

@test "k8s_pick_pod: outputs first column of selection" {
  stub_kubectl "app"
  stub_fzf_pick_first
  run bash -c "source '$BINBOX_DIR/lib/k8s.sh'; k8s_pick_pod ''"
  [ "$status" -eq 0 ]
  [ "$output" = "pod-a" ]
}

@test "k8s_pick_pod: passes -n to kubectl" {
  stub_kubectl "app"
  stub_fzf_pick_first
  run bash -c "source '$BINBOX_DIR/lib/k8s.sh'; k8s_pick_pod myns"
  [ "$status" -eq 0 ]
  grep -q 'get pods -n myns --no-headers' "$STUB_DIR/kubectl.calls"
}

@test "k8s_pick_pod: empty pod list dies" {
  make_stub kubectl 'exit 1'
  stub_fzf_pick_first
  run bash -c "source '$BINBOX_DIR/lib/k8s.sh'; k8s_pick_pod '' 2>&1"
  [ "$status" -eq 1 ]
  [[ "$output" == *"pod 목록"* ]]
}

@test "k8s_pick_pod: cancel returns 0 with empty output" {
  stub_kubectl "app"
  stub_fzf_cancel
  run bash -c "source '$BINBOX_DIR/lib/k8s.sh'; k8s_pick_pod ''"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "k8s_pick_container: single container returns 0 with empty output" {
  stub_kubectl "app"
  stub_fzf_pick_first
  run bash -c "source '$BINBOX_DIR/lib/k8s.sh'; k8s_pick_container '' my-pod"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "k8s_pick_container: multiple containers picks via fzf" {
  stub_kubectl "app sidecar"
  stub_fzf_pick_first
  run bash -c "source '$BINBOX_DIR/lib/k8s.sh'; k8s_pick_container '' my-pod"
  [ "$status" -eq 0 ]
  [ "$output" = "app" ]
}

@test "k8s_pick_container: cancel returns nonzero with empty output" {
  stub_kubectl "app sidecar"
  stub_fzf_cancel
  run bash -c "source '$BINBOX_DIR/lib/k8s.sh'; k8s_pick_container '' my-pod"
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "k8s_pick_container: kubectl failure returns 0 with empty output" {
  make_stub kubectl 'exit 1'
  stub_fzf_pick_first
  run bash -c "source '$BINBOX_DIR/lib/k8s.sh'; k8s_pick_container '' my-pod"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
