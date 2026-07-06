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

### bb 경유 호출 (일원화 완료 후 — bb만 PATH에 있으면 됨)

| 위치 | 내용 |
|------|------|
| `~/.config/nvim/lua/plugins/terminal.lua:58` | toggleterm `<leader>tp`가 `bb tm` 실행 |
| `~/.tmux.conf:160` | `bind f run-shell "tmux neww 'bb tm'"` |
| `~/.tmux.conf:163` | agents 팝업 — `if-shell "command -v bb"` + `bb agents` |

비인터랙티브 셸(tmux run-shell, nvim toggleterm)은 aliases.zsh를 읽지 않으므로
**반드시 `bb <tool>` 형태로 호출**해야 한다.

### 설정 파일 포맷 공유 (bb와 무관, 포맷 변경 시 주의)

- `~/.config/tmux-sessionizer/dirs` — nvim의 `editor.lua:7`(Snacks projects dev 루트)이
  이 파일을 **직접 파싱**한다 (`#` 주석, `~` 확장, `=` 직접 등록 prefix 포함).
  `tm`으로 통합한 뒤에도 이 경로/포맷은 그대로 유지한다 (tm go가 계속 읽는다).
  `=` 문법 추가 시 editor.lua도 함께 수정함 — 포맷을 또 바꾸면 양쪽 동기 수정 필요.
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
- [x] 개별 명령어 zsh 완성 (`completions/_binbox`) — kctx: context, kns/klog/kexec/kpf:
      namespace·pod(-n 존중), gbr: 브랜치, awsp: profile, tfsum/sec: 서브커맨드,
      dx: 도구, tm: 서브커맨드·세션·레이아웃.
      `bb <tool> <Tab>`도 `_bb`가 shift 후 `_normal`로 위임해 동일하게 동작.
      sec 서비스명은 복호화가 필요해 의도적으로 제외
- [x] **tmux 5종을 `tm` 통합 명령으로 병합** — `tm`(=`tm go`, 구 sessionizer),
      `tm attach`, `tm layout`, `tm kill [패턴]`(구 kill-sessions + kill-pattern 통합).
      설정/상태 경로(`~/.config/tmux-sessionizer/*`)는 nvim 결합 때문에 그대로 유지.
      외부 호출 지점(~/.tmux.conf bind f, nvim terminal.lua)도 `tm`으로 함께 수정
- [x] **`tm dirs` + 단일 디렉토리 직접 등록** — dirs 파일에 `=경로` 문법 추가
      (그 디렉토리 자체가 후보), `tm dirs`/`add [-d]`/`rm`/`edit`로 CLI 관리.
      nvim editor.lua 파서도 `=` 인식하도록 동기 수정
- [x] **bb 일원화 완료** — 도구 20개를 `libexec/`로 이동, PATH에는 `bb`만 노출.
      개별 명령은 `aliases.zsh`(libexec 자동 스캔, awsp는 eval 래핑 함수)로 복원.
      bb/binbox-check/Makefile/테스트 경로 갱신, 프롤로그는 `dirname/..` 기준으로 변경.
      외부 호출(tmux bind f, agents 팝업, nvim toggleterm)은 `bb <tool>`로 수정
- [x] `bb new <name>` — 프롤로그/usage/-h 템플릿이 채워진 도구를 libexec/에 생성
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
