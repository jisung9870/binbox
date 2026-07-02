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

### 단기

- [ ] 나머지 스크립트 `lib/common.sh` 마이그레이션 — 손댈 때 점진 전환
      (`tmux-sessionizer`, `tmux-kill-pattern`, `tmux-layout`, `portcheck`, `tfsum`, `tfplan`, `dx`)
- [ ] CI에 macOS runner 추가 — bash 3.2 호환성 검증
      (tfsum의 빈 배열 + `set -u` 버그처럼 Linux CI만으로는 못 잡는 문제가 실재함)
- [ ] `tmux-kill-pattern`의 y/n 확인을 `lib/common.sh confirm()`으로 교체

### 중기

- [ ] `bb new <name>` — 프롤로그/usage 템플릿이 채워진 새 스크립트 생성
- [ ] 개별 명령어 zsh 완성 확장 (kctx: context 목록, kns: namespace 목록 등)
- [ ] `awsp`에 region 전환 옵션 검토 (`AWS_REGION` export 동시 출력)
- [ ] `dx.d` 도구 추가 검토 (node, python 등 필요해지는 시점에)

### 장기 / 검토

- [ ] `agents`의 Go TUI 전환 검토 — 저장소에서 유일하게 로직이 무거운 도구.
      polling 갱신, 상태별 색상, 실시간 pane preview가 필요해지면 bubbletea로 개별 이전.
      전면 Go 이전이 아니라 이 도구 하나만 대상.
- [ ] `klog` multi-pod 동시 로그 (stern 스타일) — 필요성 생기면 stern 설치를 먼저 검토

## 완료

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
- [x] bats 테스트 51개 (lib 단위 / 인자 검증 / tfsum 파싱 / 신규 도구 / bb)
- [x] tfsum bash 3.2 빈 배열 버그 수정 (`${FLAGS[@]+...}` 관용구)
- [x] 전 스크립트 `usage()` + `-h` 통일, 에러 stderr 일관화
- [x] agents: `set -e` 미사용 사유 주석, ctrl-r reload 절대경로화

### 2026-07 — 신규 도구

- [x] git: `gbr`, `glog`
- [x] k8s: `klog`, `kexec`, `kpf`
- [x] AWS: `awsp`, `assm`
