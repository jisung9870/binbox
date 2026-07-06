# ROADMAP

binbox의 개선 방향과 계획. 완료된 항목은 기록으로 남긴다.

## 원칙

- **래퍼는 bash로 유지한다.** 도구 대부분이 fzf/tmux/kubectl/aws의 인터랙티브 글루 코드라
  Go 등으로 옮겨도 결국 외부 CLI를 호출해야 하고, 수정→커밋이면 끝나는 해커빌리티를 잃는다.
- **배포는 git이 담당한다.** 설치는 clone + PATH, 업데이트는 `bb upgrade`(git pull).
  바이너리 릴리스 파이프라인은 만들지 않는다.
- **과추상화 금지.** `lib/common.sh`는 실제로 반복되는 패턴만 담는다.
- **새 스크립트 비용 최소화.** shellcheck 대상, `bb list`, zsh 완성이 모두 자동 반영되므로
  파일 하나 추가하면 끝나는 구조를 유지한다.

## 진행 예정

### 중기

- [ ] **bb 일원화 — 개별 명령어 PATH 제거 검토** (아래 "외부 결합 지점" 선행 조치 필수)
  - 스크립트를 `libexec/` 하위로 이동해 PATH에서 숨기고 `bb`만 노출
  - 선행 조치: 외부 설정에서 개별 명령어를 직접 호출하는 곳을 먼저 수정
    - `~/.config/nvim/lua/plugins/terminal.lua:58` — toggleterm `<leader>tp`의 `cmd = "tmux-sessionizer"` → `bb tmux-sessionizer`
    - `~/.tmux.conf:159` — `bind f run-shell "tmux neww tmux-sessionizer"` → `bb tmux-sessionizer`
  - `bb list`/`resolve_tool`/`binbox-check`/`make install`의 탐색 경로를 `libexec/`로 변경
  - 자주 쓰는 명령은 `.zshrc` alias로 복원 가능 (예: `alias kctx='bb kctx'`)
- [ ] `bb new <name>` — 프롤로그/usage 템플릿이 채워진 새 스크립트 생성
- [ ] 개별 명령어 zsh 완성 확장 (kctx: context 목록, kns: namespace 목록 등)
- [ ] `awsp`에 region 전환 옵션 검토 (`AWS_REGION` export 동시 출력)
- [ ] `dx.d` 도구 추가 검토 (node, python 등 필요해지는 시점에)

### 장기 / 검토

- [ ] `agents`의 Go TUI 전환 검토 — 저장소에서 유일하게 로직이 무거운 도구.
      polling 갱신, 상태별 색상, 실시간 pane preview가 필요해지면 bubbletea로 개별 이전.
      전면 Go 이전이 아니라 이 도구 하나만 대상.
- [ ] `klog` multi-pod 동시 로그 (stern 스타일) — 필요성 생기면 stern 설치를 먼저 검토

## 외부 결합 지점

binbox 바깥의 설정이 binbox에 의존하는 곳. **명령어 이름을 바꾸거나 PATH에서 제거하기 전에
반드시 여기를 먼저 확인한다.** (2026-07 조사 기준)

### 개별 명령어 이름으로 직접 호출 (일원화 시 깨짐)

| 위치 | 내용 |
|------|------|
| `~/.config/nvim/lua/plugins/terminal.lua:58` | toggleterm `<leader>tp`가 `tmux-sessionizer` 실행 |
| `~/.tmux.conf:159` | `bind f run-shell "tmux neww tmux-sessionizer"` |

### 설정 파일 포맷 공유 (bb와 무관, 포맷 변경 시 주의)

- `~/.config/tmux-sessionizer/dirs` — nvim의 `editor.lua:7`(Telescope 프로젝트 목록)이
  이 파일을 **직접 파싱**한다 (`#` 주석, `~` 확장 규칙 포함).
  binbox 쪽에서 파일 위치/포맷을 바꾸면 nvim 쪽은 조용히 폴백으로 빠지므로
  lazyvim-config 저장소와 함께 수정해야 한다.

### binbox → 외부 방향

- `tmux-layouts/{golang,terraform}-layout`이 pane에서 `nvim`을 실행 — 읽기 전용 사용이라 영향 없음.
- `bb upgrade`는 `git -C $BINBOX_DIR`로 binbox 저장소만 pull — 다른 저장소(~/.config/nvim 등)는 건드리지 않음.
- `bb` 이름 충돌 없음 확인 (babashka/alias/zsh 함수 없음, LazyVim `<leader>bb` 키맵은 nvim 내부라 무관).

## 완료

### 2026-07 — 카테고리 스크립트 정비

- [x] `lib/k8s.sh` 추출 — klog/kexec/kpf에 3벌 복붙돼 있던 pod/컨테이너 선택 로직 통합
      (`k8s_pick_pod` / `k8s_pick_container`, bash 3.2 안전: namespace는 문자열 인자, 결과는 stdout)
- [x] 나머지 스크립트 `lib/common.sh` 마이그레이션 완료
      (tmux-sessionizer, tmux-kill-pattern, tmux-layout, portcheck, tfsum, tfplan, dx, md2jira —
      `agents`는 set -e 미사용 의도라 제외, binbox-check/doctor는 메타 도구라 제외)
- [x] CI macOS runner + bash 3.2 shim — 러너의 brew bash 5.x가 `env bash`로 풀리지 않도록
      /bin/bash를 PATH 최상단에 shim
- [x] `tmux-kill-pattern`/`portcheck` y/n 확인을 `confirm()`으로 교체
- [x] `tmux-kill-pattern`/`portcheck`/`tfplan` usage()/-h 신설 (usage 통일 마무리)
- [x] `binbox-check`에 `-P SCRIPTDIR` 추가 — repo root 밖 cwd에서 `bb check`가
      SC1091로 실패하던 버그 수정
- [x] `awsp -h`를 stdout으로 정렬 (`bb help awsp` 파이프 시 빈 화면 문제)
- [x] 테스트 확충 74개 → 106개 — klog/kexec/kpf 동작 고정 e2e, lib/k8s.sh 단위,
      confirm()/tmux-kill-pattern/portcheck y·n 플로우
- 결정: **need_cmd fzf 배치 규칙** — 인자를 다 줘도 fzf가 필요할 수 있으면 상단 체크
  (klog/kexec/kpf), 인자를 주면 fzf가 확실히 불필요하면 늦은 체크 유지 (kctx/gbr/awsp)
- 결정: **`.shellcheckrc` 만들지 않음** — disable 규칙이 0개라 설정 파일이 오히려 노이즈.
  필요해지는 시점에 재검토

### 2026-07 — 통합 진입점

- [x] `bb` 디스패처 (busybox 스타일) — 기존 명령어 유지 + 단일 진입점 추가
- [x] `bb upgrade` — git pull 기반 업데이트 + 변경 로그 출력
- [x] zsh 자동완성 (`completions/_bb`, `bb list` 기반 동적 완성)
- [x] Go 전면 이전 검토 후 기각 (위 원칙 참고)

### 2026-07 — 인프라 / 품질

- [x] `binbox-check` 자동 탐색 전환 (하드코딩 목록 제거)
- [x] Makefile (`check` / `test` / `doctor` / `install` / `ci`)
- [x] GitHub Actions CI (shellcheck + bats)
- [x] `lib/common.sh` 공통 라이브러리 + 4개 스크립트 마이그레이션
      (kctx, kns, tmux-attach, tmux-kill-sessions)
- [x] bats 테스트 스위트 도입 — 51개 (lib 단위 / 인자 검증 / tfsum 파싱 / 신규 도구 / bb)
- [x] tfsum bash 3.2 빈 배열 버그 수정 (`${FLAGS[@]+...}` 관용구)
- [x] 전 스크립트 `usage()` + `-h` 통일, 에러 stderr 일관화
- [x] agents: `set -e` 미사용 사유 주석, ctrl-r reload 절대경로화

### 2026-07 — 신규 도구

- [x] git: `gbr`, `glog`
- [x] k8s: `klog`, `kexec`, `kpf`
- [x] AWS: `awsp`, `assm`
- [x] 시크릿: `sec` (age 암호화 다중 필드 시크릿 스토어, CRUD + fzf copy + env export)
