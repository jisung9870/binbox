#!/usr/bin/env bats
# tfsum 인자 파싱 테스트 (terraform/tf-summarize 스텁 사용)
# NOTE: bats가 멀티바이트 테스트명을 처리하지 못해 테스트명은 영문 사용

load helpers/stub

setup() {
  BINBOX_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  setup_stub_dir
  make_stub terraform 'printf "%s\n" "$@" >> "'"$STUB_DIR"'/terraform.args"; echo "{}"'
  make_stub tf-summarize 'cat >/dev/null; [ "$#" -gt 0 ] && printf "%s\n" "$@" >> "'"$STUB_DIR"'/tf-summarize.args"; exit 0'
  WORK_DIR=$(mktemp -d)
  cd "$WORK_DIR"
  touch tfplan
}

teardown() {
  cd /
  rm -rf "$WORK_DIR"
  teardown_stub_dir
}

@test "tfsum -h: prints usage and exits 0" {
  run "$BINBOX_DIR/tfsum" -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"tf-summarize wrapper"* ]]
}

@test "tfsum: unknown subcommand exits 2" {
  run "$BINBOX_DIR/tfsum" badcmd
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown subcommand"* ]]
}

@test "tfsum: default summary runs tf-summarize with no flags" {
  run "$BINBOX_DIR/tfsum"
  [ "$status" -eq 0 ]
  [ ! -s "$STUB_DIR/tf-summarize.args" ]
}

@test "tfsum tree: passes -tree flag" {
  run "$BINBOX_DIR/tfsum" tree
  [ "$status" -eq 0 ]
  grep -qx -- "-tree" "$STUB_DIR/tf-summarize.args"
}

@test "tfsum md outfile: passes -md and -out" {
  run "$BINBOX_DIR/tfsum" md summary.md
  [ "$status" -eq 0 ]
  grep -qx -- "-md" "$STUB_DIR/tf-summarize.args"
  grep -qx -- "-out=summary.md" "$STUB_DIR/tf-summarize.args"
}

@test "tfsum md outfile planfile: uses given plan file" {
  touch other.tfplan
  run "$BINBOX_DIR/tfsum" md summary.md other.tfplan
  [ "$status" -eq 0 ]
  grep -qx -- "other.tfplan" "$STUB_DIR/terraform.args"
}

@test "tfsum md a b c: extra args exit 2" {
  run "$BINBOX_DIR/tfsum" md a b c
  [ "$status" -eq 2 ]
  [[ "$output" == *"unexpected argument"* ]]
}

@test "tfsum: missing plan file errors" {
  rm tfplan
  run "$BINBOX_DIR/tfsum" tree
  [ "$status" -eq 1 ]
  [[ "$output" == *"plan file not found"* ]]
}

@test "tfsum: respects TFPLAN_FILE env var" {
  touch qa.tfplan
  run env TFPLAN_FILE=qa.tfplan "$BINBOX_DIR/tfsum" tree
  [ "$status" -eq 0 ]
  grep -qx -- "qa.tfplan" "$STUB_DIR/terraform.args"
}
