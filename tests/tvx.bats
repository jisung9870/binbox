#!/usr/bin/env bats
# tvx Trivy wrapper argument/policy tests

load helpers/stub

setup() {
  BINBOX_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  TVX="$BINBOX_DIR/libexec/tvx"
  setup_stub_dir
  make_stub trivy
}

teardown() {
  teardown_stub_dir
}

assert_args() {
  local expected="$1"
  [ "$(cat "$STUB_DIR/trivy.args")" = "$expected" ]
}

@test "tvx help exits 0" {
  run "$TVX" -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"사용법"* ]]

  run "$TVX" ci --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"TVX_CI_SEVERITY"* ]]
}

@test "tvx image enables all project scanners" {
  run "$TVX" image nginx:latest --ignore-unfixed
  [ "$status" -eq 0 ]
  assert_args $'image\n--scanners\nvuln,misconfig,secret\nnginx:latest\n--ignore-unfixed'
}

@test "tvx repo defaults to current directory" {
  run "$TVX" repo
  [ "$status" -eq 0 ]
  assert_args $'repo\n--scanners\nvuln,misconfig,secret\n.'
}

@test "tvx config defaults to current directory" {
  run "$TVX" config
  [ "$status" -eq 0 ]
  assert_args $'config\n.'
}

@test "tvx ci applies fixed policy" {
  run "$TVX" ci repo .
  [ "$status" -eq 0 ]
  assert_args $'repo\n--scanners\nvuln,misconfig,secret\n--severity\nHIGH,CRITICAL\n--exit-code\n1\n.'
}

@test "tvx ci accepts severity environment" {
  run env TVX_CI_SEVERITY=CRITICAL "$TVX" ci config infra
  [ "$status" -eq 0 ]
  assert_args $'config\n--severity\nCRITICAL\n--exit-code\n1\ninfra'
}

@test "tvx ci rejects invalid severity" {
  run env TVX_CI_SEVERITY=high "$TVX" ci repo
  [ "$status" -eq 1 ]
  [[ "$output" == *"올바르지 않은 TVX_CI_SEVERITY"* ]]
}

@test "tvx ci rejects policy override flags" {
  run "$TVX" ci repo . --severity LOW
  [ "$status" -eq 1 ]
  [[ "$output" == *"재정의할 수 없습니다"* ]]
}

@test "tvx sbom generates cyclonedx" {
  run "$TVX" sbom image app:v1 -o sbom.json
  [ "$status" -eq 0 ]
  assert_args $'image\n--format\ncyclonedx\napp:v1\n-o\nsbom.json'
}

@test "tvx report selects format and scanners" {
  run "$TVX" report sarif repo . -o report.sarif
  [ "$status" -eq 0 ]
  assert_args $'repo\n--scanners\nvuln,misconfig,secret\n--format\nsarif\n.\n-o\nreport.sarif'
}

@test "tvx k8s disables node collector by default" {
  make_stub kubectl 'echo dev-context'
  run "$TVX" k8s
  [ "$status" -eq 0 ]
  [[ "$output" == *"dev-context"* ]]
  assert_args $'kubernetes\n--report\nsummary\n--disable-node-collector'
}

@test "tvx k8s collector cancel does not run trivy" {
  rm -f "$STUB_DIR/trivy.args"
  run bash -c "printf 'n' | '$TVX' k8s prod --with-node-collector"
  [ "$status" -eq 0 ]
  [[ "$output" == *"취소"* ]]
  [ ! -f "$STUB_DIR/trivy.args" ]
}

@test "tvx k8s collector runs after confirmation" {
  run bash -c "printf 'y' | '$TVX' k8s prod --with-node-collector --skip-images"
  [ "$status" -eq 0 ]
  assert_args $'kubernetes\n--report\nsummary\n--skip-images\nprod'
}

@test "tvx clean defaults to scan cache" {
  run "$TVX" clean
  [ "$status" -eq 0 ]
  assert_args $'clean\n--scan-cache'
}

@test "tvx propagates trivy failure" {
  make_stub trivy 'exit 7'
  run "$TVX" image broken:tag
  [ "$status" -eq 7 ]
}

@test "tvx missing trivy prints install hint" {
  rm -f "$STUB_DIR/trivy"
  run env PATH="/usr/bin:/bin" "$TVX" repo
  [ "$status" -eq 1 ]
  [[ "$output" == *"trivy"* ]]
}
