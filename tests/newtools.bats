#!/usr/bin/env bats
# 신규 유틸리티(kx/gx/assume/assm) 인자 검증 테스트
# NOTE: bats가 멀티바이트 테스트명을 처리하지 못해 테스트명은 영문 사용

load helpers/stub

setup() {
  BINBOX_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  setup_stub_dir
}

teardown() {
  teardown_stub_dir
}

@test "new tools -h: all exit 0" {
  for tool in kx gx assume assm; do
    run "$BINBOX_DIR/libexec/$tool" -h
    [ "$status" -eq 0 ]
  done
}

@test "gx br: errors outside a git repo" {
  dir=$(mktemp -d)
  run bash -c "cd '$dir' && GIT_CEILING_DIRECTORIES='$dir' '$BINBOX_DIR/libexec/gx' br 2>&1"
  [ "$status" -eq 1 ]
  [[ "$output" == *"git 저장소"* ]]
  rm -rf "$dir"
}

@test "gx br <branch>: switches directly without fzf" {
  repo=$(mktemp -d)
  git -C "$repo" init -q -b main
  git -C "$repo" -c user.email=t@t -c user.name=t commit --allow-empty -qm init
  git -C "$repo" branch feature
  run bash -c "cd '$repo' && '$BINBOX_DIR/libexec/gx' br feature && git branch --show-current"
  [ "$status" -eq 0 ]
  [[ "$output" == *"feature"* ]]
  rm -rf "$repo"
}

@test "gx new <name>: creates and switches" {
  repo=$(mktemp -d)
  git -C "$repo" init -q -b main
  git -C "$repo" -c user.email=t@t -c user.name=t commit --allow-empty -qm init
  run bash -c "cd '$repo' && '$BINBOX_DIR/libexec/gx' new feature && git branch --show-current"
  [ "$status" -eq 0 ]
  [[ "$output" == *"feature"* ]]
  rm -rf "$repo"
}

@test "gx new: errors outside a git repo" {
  dir=$(mktemp -d)
  run bash -c "cd '$dir' && GIT_CEILING_DIRECTORIES='$dir' '$BINBOX_DIR/libexec/gx' new x 2>&1"
  [ "$status" -eq 1 ]
  [[ "$output" == *"git 저장소"* ]]
  rm -rf "$dir"
}

@test "gx clean: deletes fzf-selected branches after confirm" {
  repo=$(mktemp -d)
  git -C "$repo" init -q -b main
  git -C "$repo" -c user.email=t@t -c user.name=t commit --allow-empty -qm init
  git -C "$repo" branch feature-a
  git -C "$repo" branch feature-b
  make_stub fzf 'cat'
  run bash -c "cd '$repo' && printf 'y' | '$BINBOX_DIR/libexec/gx' clean"
  [ "$status" -eq 0 ]
  run git -C "$repo" branch --list
  [[ "$output" != *"feature-a"* ]]
  [[ "$output" != *"feature-b"* ]]
  rm -rf "$repo"
}

@test "gx clean: n cancels without deleting" {
  repo=$(mktemp -d)
  git -C "$repo" init -q -b main
  git -C "$repo" -c user.email=t@t -c user.name=t commit --allow-empty -qm init
  git -C "$repo" branch feature-a
  make_stub fzf 'cat'
  run bash -c "cd '$repo' && printf 'n' | '$BINBOX_DIR/libexec/gx' clean"
  [ "$status" -eq 0 ]
  [[ "$output" == *"취소"* ]]
  run git -C "$repo" branch --list
  [[ "$output" == *"feature-a"* ]]
  rm -rf "$repo"
}

@test "gx clean: fzf cancel exits 0 without deleting" {
  repo=$(mktemp -d)
  git -C "$repo" init -q -b main
  git -C "$repo" -c user.email=t@t -c user.name=t commit --allow-empty -qm init
  git -C "$repo" branch feature-a
  make_stub fzf 'cat >/dev/null; exit 130'
  run bash -c "cd '$repo' && '$BINBOX_DIR/libexec/gx' clean"
  [ "$status" -eq 0 ]
  run git -C "$repo" branch --list
  [[ "$output" == *"feature-a"* ]]
  rm -rf "$repo"
}

@test "gx clean: unmerged branch force-deleted after second confirm" {
  repo=$(mktemp -d)
  git -C "$repo" init -q -b main
  git -C "$repo" -c user.email=t@t -c user.name=t commit --allow-empty -qm init
  git -C "$repo" checkout -q -b wip
  git -C "$repo" -c user.email=t@t -c user.name=t commit --allow-empty -qm work
  git -C "$repo" checkout -q main
  make_stub fzf 'cat'
  run bash -c "cd '$repo' && printf 'yy' | '$BINBOX_DIR/libexec/gx' clean"
  [ "$status" -eq 0 ]
  run git -C "$repo" branch --list
  [[ "$output" != *"wip"* ]]
  rm -rf "$repo"
}

@test "gx clean: unmerged branch kept when force declined" {
  repo=$(mktemp -d)
  git -C "$repo" init -q -b main
  git -C "$repo" -c user.email=t@t -c user.name=t commit --allow-empty -qm init
  git -C "$repo" checkout -q -b wip
  git -C "$repo" -c user.email=t@t -c user.name=t commit --allow-empty -qm work
  git -C "$repo" checkout -q main
  make_stub fzf 'cat'
  run bash -c "cd '$repo' && printf 'yn' | '$BINBOX_DIR/libexec/gx' clean"
  [ "$status" -eq 1 ]
  run git -C "$repo" branch --list
  [[ "$output" == *"wip"* ]]
  rm -rf "$repo"
}

@test "gx clean --gone: targets only branches with gone upstream" {
  remote=$(mktemp -d)
  repo=$(mktemp -d)
  git init -q --bare "$remote"
  git -C "$repo" init -q -b main
  git -C "$repo" -c user.email=t@t -c user.name=t commit --allow-empty -qm init
  git -C "$repo" remote add origin "$remote"
  git -C "$repo" push -q origin main
  git -C "$repo" -c user.email=t@t -c user.name=t checkout -q -b feature
  git -C "$repo" push -q -u origin feature
  git -C "$repo" checkout -q main
  git -C "$repo" push -q origin --delete feature
  git -C "$repo" fetch -q --prune
  git -C "$repo" branch keep
  make_stub fzf 'cat'
  run bash -c "cd '$repo' && printf 'y' | '$BINBOX_DIR/libexec/gx' clean --gone"
  [ "$status" -eq 0 ]
  run git -C "$repo" branch --list
  [[ "$output" != *"feature"* ]]
  [[ "$output" == *"keep"* ]]
  rm -rf "$remote" "$repo"
}

@test "gx clean: errors outside a git repo" {
  dir=$(mktemp -d)
  run bash -c "cd '$dir' && GIT_CEILING_DIRECTORIES='$dir' '$BINBOX_DIR/libexec/gx' clean 2>&1"
  [ "$status" -eq 1 ]
  [[ "$output" == *"git 저장소"* ]]
  rm -rf "$dir"
}

@test "gx clean: unknown option errors" {
  run "$BINBOX_DIR/libexec/gx" clean --bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"알 수 없는 옵션"* ]]
}

@test "kx log: unknown option errors" {
  run "$BINBOX_DIR/libexec/kx" log --bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"알 수 없는 옵션"* ]]
}

@test "kx log: --tail requires a number" {
  run "$BINBOX_DIR/libexec/kx" log --tail abc
  [ "$status" -eq 1 ]
}

@test "kx pf: -n requires a value" {
  run "$BINBOX_DIR/libexec/kx" pf -n
  [ "$status" -eq 1 ]
}

@test "assm: missing aws cli errors with hint" {
  run env PATH="/usr/bin:/bin" "$BINBOX_DIR/libexec/assm" 2>&1
  [ "$status" -eq 1 ]
  [[ "$output" == *"aws"* ]]
}
