# binbox

개인 CLI 스크립트 모음. Mac / WSL 환경에서 `$PATH`에 등록해 사용한다.

```bash
# .zshrc
export PATH="$HOME/binbox:$PATH"
```

## 구조

```
binbox/
├── Makefile                # make check / test / doctor / install
├── lib/
│   └── common.sh           # 공통 함수 (die, need_cmd, fzf_pick, ...)
├── tests/                  # bats 테스트
├── binbox-check            # 개발용 shellcheck 일괄 실행 (자동 탐색)
├── binbox-doctor           # 로컬 의존성 점검
├── dx                      # Docker 기반 도구 실행기
├── dx.d/                   # dx 도구 설정 디렉토리
│   ├── ansible
│   ├── ubuntu
│   ├── terraform
│   └── golang
├── images/                 # Docker 이미지 빌드 파일
│   └── ansible/Dockerfile
├── tmux-attach             # fzf로 tmux 세션 선택/생성
├── tmux-sessionizer        # 프로젝트 디렉토리 → tmux 세션
├── tmux-layout             # fzf로 레이아웃 선택 후 세션 생성
├── tmux-kill-sessions      # fzf 다중 선택으로 세션 삭제
├── tmux-kill-pattern       # 패턴 매칭으로 세션 일괄 삭제
├── agents                  # Claude/Codex tmux pane 상태 조회 및 점프
├── tmux-layouts/           # tmux 레이아웃 정의
├── gbr                     # fzf 기반 git 브랜치 전환
├── glog                    # fzf 기반 git log 탐색
├── gitroot                 # git 저장소 루트로 cd
├── kctx                    # fzf 기반 kubectl context 전환
├── kns                     # fzf 기반 kubectl namespace 전환
├── klog                    # fzf로 pod 선택 후 logs -f
├── kexec                   # fzf로 pod 선택 후 셸 접속
├── kpf                     # fzf로 pod 선택 후 port-forward
├── awsp                    # fzf 기반 AWS_PROFILE 전환
├── assm                    # fzf로 EC2 선택 후 SSM 세션 접속
├── portcheck               # 포트 사용 프로세스 확인
├── md2jira                 # md-to-jiratext CLI 실행
├── tfplan                  # terraform plan을 tfplan 파일로 저장
└── tfsum                   # terraform plan 요약 출력
```

## 개발/관리

```bash
make check     # shellcheck 일괄 실행 (스크립트 자동 탐색)
make test      # bats 테스트 (brew install bats-core)
make doctor    # 의존성 점검
make install   # 실행 권한 재적용 + PATH 안내
```

- `binbox-check`는 bash shebang을 가진 스크립트를 자동 탐색하므로 새 스크립트를 목록에 추가할 필요가 없다.
- GitHub Actions(`.github/workflows/ci.yml`)가 push/PR마다 shellcheck + bats를 실행한다.
- 공통 함수는 `lib/common.sh`에 있다. 새 스크립트는 아래 프롤로그로 source:

```bash
_self=$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")
BINBOX_DIR=$(cd "$(dirname "$_self")" && pwd)
# shellcheck source=lib/common.sh
source "$BINBOX_DIR/lib/common.sh" || { echo "lib/common.sh not found" >&2; exit 1; }
```

## dx — Docker 기반 도구 실행기

호스트에 도구를 설치하지 않고 Docker 컨테이너로 실행한다. `dx.d/` 디렉토리에 설정 파일을 추가하면 자동으로 사용 가능.

```bash
# 사용 가능한 도구 목록
dx --list

# 전체/도구별 도움말
dx --help
dx --help ansible

# 로컬 Dockerfile이 있는 도구 빌드
dx --build ansible

# ansible 실행
dx ansible ansible-playbook site.yml

# 컨테이너 안에서 bash 접근
dx ubuntu

# terraform plan
dx terraform plan

# golang 개발
dx golang go test ./...
```

`dx`는 터미널에서 실행할 때만 Docker에 `-it`를 전달하고, 파이프/CI 같은
비대화형 실행에서는 `-i`만 사용한다. 각 `dx.d/*` 설정은 `DOCKER_IMAGE`와
배열 형태의 `DOCKER_OPTS`가 필요하다.

### 도구 추가 방법

`dx.d/` 디렉토리에 파일을 만들고 `DOCKER_IMAGE`와 `DOCKER_OPTS`를 정의한다.

```bash
# dx.d/mytool
DOCKER_IMAGE="myimage:latest"
DOCKER_OPTS=(
  -v "$HOME/.config/mytool:/root/.config/mytool"
  -e "MY_ENV=value"
)
```

## tmux 스크립트

| 명령어 | 설명 |
|--------|------|
| `tmux-sessionizer` | 프로젝트 디렉토리를 fzf로 선택하여 tmux 세션 생성/전환 |
| `tmux-attach` | 기존 세션 선택 또는 새 세션 생성 |
| `tmux-layout` | 레이아웃을 선택하여 세션 생성 (golang, k8s, terraform) |
| `tmux-kill-sessions` | fzf 다중 선택으로 세션 삭제 |
| `tmux-kill-pattern` | 패턴 매칭으로 세션 일괄 삭제 |
| `agents` | Claude/Codex tmux pane 상태 조회 및 fzf 점프 |

```bash
# 프로젝트 선택 → 세션 생성
tmux-sessionizer

# 레이아웃 선택 → 세션 생성
tmux-layout my-project ~/home/projects/my-project

# k8s 패턴 세션 일괄 삭제
tmux-kill-pattern k8s

# Claude/Codex pane 목록
agents --list

# 계정/상태 요약
agents --usage

# fzf로 agent pane 선택 후 이동
agents
```

### tmux-sessionizer 설정

프로젝트 디렉토리 목록은 외부 설정 파일로 관리한다. 머신별로 설정 파일만 다르게 두면 스크립트 수정 없이 사용 가능.

```bash
# 설정 파일 생성
mkdir -p ~/.config/tmux-sessionizer
cat > ~/.config/tmux-sessionizer/dirs << 'EOF'
~/home/projects
~/home/work
~/home/lab
~/.config
EOF
```

설정 파일이 없으면 스크립트 내 기본 경로(`~/home/projects`, `~/home/work`)를 사용한다.
프로젝트 목록은 hidden 디렉토리를 제외하고 표시하며, 최근 선택한 프로젝트는
`$XDG_STATE_HOME/tmux-sessionizer/recent` 또는 `~/.local/state/tmux-sessionizer/recent`에 저장되어 다음 실행 때 먼저 표시된다.

### 레이아웃 추가

`tmux-layouts/` 디렉토리에 `*-layout` 파일을 추가한다. `tmux-layout` 명령어가 자동으로 인식한다.

## git 유틸리티

```bash
# 브랜치 전환 (최근 커밋 순, preview로 로그 확인)
gbr
gbr -a               # 원격 브랜치 포함
gbr feature/login    # 직접 전환

# 커밋 탐색 (Enter로 해시 출력 → 다른 명령과 조합)
glog
git rebase -i $(glog)^
git show $(glog)

# git 저장소 루트로 이동
cd $(gitroot)
eval "$(gitroot --cd)"
```

## Kubernetes 유틸리티

```bash
# context / namespace 전환 (fzf)
kctx
kns

# 특정 context/namespace 직접 지정
kctx my-cluster
kns monitoring

# pod 로그 팔로우 (다중 컨테이너면 2차 선택)
klog
klog -n monitoring --tail 500

# pod 셸 접속 (bash 없으면 sh)
kexec
kexec -n monitoring my-pod

# port-forward (containerPort 자동 감지)
kpf
kpf my-pod 9000:8080
```

## AWS 유틸리티

```bash
# AWS_PROFILE 전환 — 자식 프로세스는 부모 셸 환경을 못 바꾸므로 eval 사용
eval "$(awsp)"
eval "$(awsp dev)"

# .zshrc에 alias 등록 추천
alias awsp='eval "$(command awsp)"'

# EC2 인스턴스 선택 후 SSM 세션 접속 (awsp로 profile 설정 후 사용)
assm
assm i-0123456789abcdef0
```

## 기타 유틸리티

```bash
# 로컬 의존성 점검
binbox-doctor

# 개발용 shellcheck 일괄 실행
binbox-check

# 포트 사용 프로세스 확인
portcheck 8080

# md-to-jiratext 실행 (위치가 다르면 MD2JIRA_HOME으로 지정)
md2jira input.md

# terraform plan 저장 후 요약
tfplan
tfsum tree
tfsum md plan-summary.md
```

## 요구 사항

`binbox-doctor`는 core dependency 누락만 실패로 처리하고, optional dependency는
경고로만 표시한다.

Core:
- Docker
- tmux
- fzf (`brew install fzf`)
- git
- lsof (portcheck 사용 시, macOS 기본 포함)

Optional:
- kubectl (kctx, kns, klog, kexec, kpf 사용 시)
- terraform, tf-summarize (tfplan, tfsum 사용 시)
- aws cli, session-manager-plugin (awsp, assm 사용 시)
- shellcheck (개발/검증 시 선택)
- bats-core (`make test` 사용 시)
- ss/iproute2 (Linux portcheck 사용 시, 없으면 lsof로 대체)

## 설치

```bash
git clone https://github.com/<your-username>/binbox.git ~/binbox

# .zshrc에 추가
echo 'export PATH="$HOME/binbox:$PATH"' >> ~/.zshrc
source ~/.zshrc

# 실행 권한 부여
cd ~/binbox && make install
```
