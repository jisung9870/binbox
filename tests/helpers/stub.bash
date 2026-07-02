# 테스트용 스텁 헬퍼
# make_stub <이름> [스크립트본문] — $STUB_DIR에 가짜 명령어 생성
# 본문 생략 시 받은 인자를 $STUB_DIR/<이름>.args에 기록하고 0 반환

setup_stub_dir() {
  STUB_DIR=$(mktemp -d)
  PATH="$STUB_DIR:$PATH"
  export STUB_DIR PATH
}

teardown_stub_dir() {
  [[ -n "${STUB_DIR:-}" ]] && rm -rf "$STUB_DIR"
}

make_stub() {
  local name="$1" body="${2:-}"
  if [[ -z "$body" ]]; then
    body="printf '%s\\n' \"\$@\" >> \"$STUB_DIR/$name.args\"; exit 0"
  fi
  printf '#!/usr/bin/env bash\n%s\n' "$body" > "$STUB_DIR/$name"
  chmod +x "$STUB_DIR/$name"
}
