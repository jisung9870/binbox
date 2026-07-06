# binbox

개인 CLI 스크립트 모음. tmux / git / Kubernetes / AWS / Terraform / Docker 워크플로우를
fzf 기반 인터랙티브 명령어로 감싼다. Mac / WSL 환경에서 사용.

## 설치

```bash
git clone https://github.com/<your-username>/binbox.git ~/binbox

# .zshrc에 추가
echo 'export PATH="$HOME/binbox:$PATH"' >> ~/.zshrc
echo 'fpath=(~/binbox/completions $fpath)' >> ~/.zshrc   # bb + 개별 명령어 자동완성, compinit 전에 위치
echo 'source ~/binbox/aliases.zsh' >> ~/.zshrc            # 개별 명령(tm, kctx 등) alias 복원
# 완성이 안 보이면 캐시 재생성: rm -f ~/.zcompdump && exec zsh
source ~/.zshrc

# 실행 권한 부여 + 의존성 점검
cd ~/binbox && make install && make doctor

# 이후 업데이트
bb upgrade
```

## bb — 통합 진입점

도구 실체는 `libexec/`에 있고 **PATH에는 `bb` 하나만 노출된다** (이름 충돌·PATH 오염 방지).
개별 명령어(`tm`, `kctx` 등)는 `aliases.zsh`를 source하면 alias로 복원되어 기존처럼 쓸 수 있다.
tmux/nvim 등 비인터랙티브 환경에서는 alias가 없으므로 `bb tm`처럼 호출한다.

```bash
bb                # 사용법 + 도구 목록
bb list           # 도구 목록
bb help klog      # 도구별 도움말 (= klog -h)
bb kctx           # 도구 실행 (= kctx)
bb doctor         # = binbox-doctor
bb check          # = binbox-check
bb upgrade        # binbox 업데이트 (git pull --ff-only + 변경 로그)
bb <Tab>          # zsh 자동완성
```

## 도구 목록

### tmux

| 명령어 | 설명 |
|--------|------|
| `tm` (= `tm go`) | 프로젝트 디렉토리를 fzf로 선택하여 세션 생성/전환 (최근 항목 우선) |
| `tm attach` | 기존 세션 선택 또는 새 세션 생성 |
| `tm layout` | 레이아웃 선택 후 세션 생성 (golang, k8s, terraform) |
| `tm kill [패턴]` | fzf 다중 선택 / 패턴 매칭으로 세션 삭제 |
| `tm dirs` | 프로젝트 디렉토리 목록 관리 (add / rm / edit) |
| `agents` | Claude/Codex tmux pane 상태 조회 및 fzf 점프 |

```bash
tm                      # 프로젝트 선택 → 세션 생성
tm layout my-proj ~/w/p # 레이아웃 선택 → 세션 생성
tm kill k8s             # k8s 패턴 세션 일괄 삭제
tm dirs add ~/home/poc  # 부모 디렉토리 등록 (자식들이 후보)
tm dirs add -d ~/binbox # 단일 디렉토리 직접 등록
agents                  # agent pane 선택 후 이동 (--list, --usage)
```

### git

| 명령어 | 설명 |
|--------|------|
| `gbr` | fzf 브랜치 전환 (최근 커밋 순, `-a`로 원격 포함) |
| `glog` | fzf 커밋 탐색, Enter로 해시 출력 (다른 명령과 조합) |
| `gitroot` | 저장소 루트 경로 출력 (`--cd`로 eval 이동) |

```bash
gbr                        # 브랜치 선택 (preview: 최근 로그)
glog                       # 커밋 탐색 (preview: diff)
git rebase -i $(glog)^     # 선택 커밋부터 rebase
cd $(gitroot)              # 저장소 루트로 이동
```

### Kubernetes

| 명령어 | 설명 |
|--------|------|
| `kctx` / `kns` | context / namespace 전환 |
| `klog` | pod 선택 → `logs -f` (다중 컨테이너 지원, `--tail`) |
| `kexec` | pod 선택 → 셸 접속 (bash 없으면 sh) |
| `kpf` | pod 선택 → port-forward (containerPort 자동 감지) |

```bash
kctx my-cluster            # 인자 주면 fzf 없이 직접 전환
klog -n monitoring
kexec
kpf my-pod 9000:8080
```

### AWS

| 명령어 | 설명 |
|--------|------|
| `awsp` | AWS_PROFILE 전환 (eval 패턴) |
| `assm` | 실행 중 EC2 선택 → SSM 세션 접속 |

```bash
eval "$(awsp)"             # 자식 프로세스는 부모 셸 env를 못 바꾸므로 eval 필요
alias awsp='eval "$(command awsp)"'   # .zshrc 등록 추천
assm                       # awsp로 profile 설정 후 사용
```

### Terraform

| 명령어 | 설명 |
|--------|------|
| `tfplan` | `terraform plan -out=tfplan` (인자 패스스루) |
| `tfsum` | plan 요약 (tree / stree / draw / md / json) |

```bash
tfplan && tfsum tree
tfsum md plan-summary.md
```

### 시크릿 — sec

개인 토큰/테스트 계정 등의 비밀값을 age 암호화 JSON 파일로 관리한다.
서비스 하나에 user/password/url/token 같은 필드를 여러 개 담는 구조.

| 명령어 | 설명 |
|--------|------|
| `sec` | age 암호화 시크릿 스토어 CRUD (init/set/get/list/copy/env/rm/edit) |

```bash
sec init                            # age key + 빈 스토어 생성 (최초 1회)
printf '%s' "$TOKEN" | sec set mydb token   # 값은 stdin/숨김 입력으로만 (argv 금지)
psql "$(sec get mydb url)"          # 스크립트에 값 주입
eval "$(sec env mydb)"              # MYDB_USER, MYDB_PASSWORD ... export
sec copy                            # fzf 선택 → 클립보드 (화면 미노출)
sec edit                            # $EDITOR로 전체 JSON 편집
```

- 스토어: `~/.config/binbox/secrets.json.age` (git 백업 가능),
  키: `~/.config/binbox/age.key` (**별도 백업 필수, git 금지**)
- 경로는 `BINBOX_SECRETS_FILE` / `BINBOX_AGE_KEY`로 변경 가능.
- `list`/`copy`/에러 메시지에 값이 노출되지 않고, `edit` 외에는 평문이 디스크에 닿지 않는다.

### Docker — dx

호스트에 도구를 설치하지 않고 컨테이너로 실행한다. `dx.d/`에 설정 파일을 추가하면 자동 인식.

```bash
dx --list                  # 사용 가능한 도구 (ansible, golang, terraform, ubuntu)
dx --help ansible
dx --build ansible         # images/<tool>/Dockerfile 빌드
dx ansible ansible-playbook site.yml
dx ubuntu                  # 컨테이너 bash 접근
```

터미널에서만 `-it`를 전달하고 파이프/CI에서는 `-i`만 사용한다.
도구 추가: `dx.d/<tool>` 파일에 `DOCKER_IMAGE`와 배열 `DOCKER_OPTS` 정의.

```bash
# dx.d/mytool
DOCKER_IMAGE="myimage:latest"
DOCKER_OPTS=(
  -v "$HOME/.config/mytool:/root/.config/mytool"
)
```

### 기타

| 명령어 | 설명 |
|--------|------|
| `portcheck` | 포트 사용 프로세스 확인 (`--kill`로 종료) |
| `md2jira` | md-to-jiratext 실행 (`MD2JIRA_HOME`으로 위치 지정) |
| `binbox-doctor` | 의존성 점검 (core 누락만 실패) |
| `binbox-check` | shellcheck 일괄 실행 (스크립트 자동 탐색) |

## 설정

### tm 프로젝트 목록

프로젝트 디렉토리 목록은 `~/.config/tmux-sessionizer/dirs`로 관리한다. 머신별로 파일만
다르게 두면 된다. (경로는 구 tmux-sessionizer 시절 그대로 — nvim이 이 파일을 직접
파싱하므로 유지)

```bash
tm dirs                 # 목록/상태 확인 (부모/직접/죽은 경로)
tm dirs add ~/home/poc  # 부모로 추가 — depth-1 자식들이 후보 (경로 생략 시 $PWD)
tm dirs add -d ~/binbox # 직접 등록 — 그 디렉토리 자체가 후보
tm dirs rm              # fzf 다중 선택으로 제거
tm dirs edit            # $EDITOR로 직접 편집
```

파일 포맷 (한 줄에 하나, `~` 사용 가능, `#` 주석):

```
~/home/projects   # 부모 — 자식 디렉토리들이 후보
=~/binbox         # '=' prefix — 이 디렉토리 자체가 후보
```

설정 파일이 없으면 기본 경로(`~/home/projects`, `~/home/work`)를 사용한다.
최근 선택 항목은 `~/.local/state/tmux-sessionizer/recent`에 저장되어 먼저 표시된다.

### tmux 레이아웃 추가

`tmux-layouts/`에 실행 가능한 `*-layout` 파일을 추가하면 `tm layout`이 자동 인식한다.

## 개발

```bash
make check     # shellcheck 일괄 실행 (bash shebang 스크립트 자동 탐색)
make test      # bats 테스트 (brew install bats-core)
make doctor    # 의존성 점검
make ci        # check + test
```

- GitHub Actions(`.github/workflows/ci.yml`)가 push/PR마다 `make ci`에 해당하는 검사를 실행한다.
- 새 스크립트는 자동으로 shellcheck 대상에 포함되고 `bb list`에도 자동으로 나타난다.
- 공통 함수(`die`, `need_cmd`, `fzf_pick`, `confirm`, `sanitize_session`)는 `lib/common.sh`에 있다.
  새 스크립트는 아래 프롤로그로 source:

```bash
_self=$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")
BINBOX_DIR=$(cd "$(dirname "$_self")" && pwd)
# shellcheck source=lib/common.sh
source "$BINBOX_DIR/lib/common.sh" || { echo "lib/common.sh not found" >&2; exit 1; }
```

향후 계획은 [ROADMAP.md](ROADMAP.md) 참고.

## 요구 사항

`binbox-doctor`가 점검한다. core 누락만 실패로 처리하고 optional은 경고만 표시.

**Core**: docker, tmux, fzf, git, lsof(macOS 기본)

**Optional**:
- kubectl — kctx, kns, klog, kexec, kpf
- terraform, tf-summarize — tfplan, tfsum
- aws cli, session-manager-plugin — awsp, assm
- age, jq — sec
- shellcheck, bats-core — 개발용
- ss/iproute2 — Linux portcheck (없으면 lsof 대체)
