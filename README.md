# binbox

개인 CLI 스크립트 모음. tmux / git / Kubernetes / AWS / Terraform / Docker 워크플로우를
fzf 기반 인터랙티브 명령어로 감싼다. Mac / WSL 환경에서 사용.

## 설치

```bash
git clone https://github.com/<your-username>/binbox.git ~/binbox

~/binbox/bb setup   # 링크(~/.local/bin/bb) + zsh/bash rc 자동 구성 (재실행 안전)
exec $SHELL         # 새 셸에 적용
bb doctor           # 의존성 점검

# 이후 업데이트
bb upgrade
```

`bb setup`이 하는 일:

1. `~/.local/bin/bb` 심볼릭 링크 생성 (repo 위치 무관, PATH에는 표준 경로만 추가)
2. 로그인 셸 감지(`$SHELL`) → `.zshrc` 또는 `.bashrc`에 마커 블록(`# >>> binbox >>>`)으로
   `shell/init.zsh`/`shell/init.bash` source 라인 등록
3. rc 블록은 최소한만 — PATH/자동완성/alias 로직은 repo의 `shell/init.*`에 있어
   이후 변경은 `bb upgrade`만으로 반영된다 (rc 재수정 불필요)

재실행하면 기존 설정은 그대로 두고("이미 최신") 변경분만 갱신한다. repo를 옮겼거나
zsh/bash 둘 다 쓰면 `bb setup --shell bash`처럼 지정해 각각 구성한다.

<details>
<summary>수동 설치 (rc 자동 수정을 원하지 않는 경우)</summary>

```bash
# .zshrc에 추가
echo 'export PATH="$HOME/binbox:$PATH"' >> ~/.zshrc
echo 'fpath=(~/binbox/completions $fpath)' >> ~/.zshrc   # bb + 개별 명령어 자동완성, compinit 전에 위치
echo 'source ~/binbox/aliases.zsh' >> ~/.zshrc            # 개별 명령(tm, kx 등) alias 복원
# 완성이 안 보이면 캐시 재생성: rm -f ~/.zcompdump && exec zsh
```

bash는 `source ~/binbox/shell/init.bash` 한 줄이면 된다 (PATH + alias + bb 완성 포함).

</details>

### WSL / Linux

bash가 로그인 셸이면 `bb setup`이 자동으로 `.bashrc`를 구성한다. 도구 스크립트는 전부
bash라 그대로 동작하며, 의존성만 설치하면 된다 (`bb doctor`가 OS에 맞는 힌트를 보여준다):

```bash
sudo apt install tmux fzf git jq age lsof shellcheck bats
```

- `sec copy` 클립보드: WSL은 `clip.exe`가 기본 동작, Linux 데스크톱은 `wl-copy`(Wayland) 또는 `xclip` 필요
- docker: Docker Desktop의 WSL integration 활성화 또는 `sudo apt install docker.io`
- 자동완성: zsh는 개별 명령까지, bash는 `bb <Tab>`만 지원

## bb — 통합 진입점

도구 실체는 `libexec/`에 있고 **PATH에는 `bb` 하나만 노출된다** (이름 충돌·PATH 오염 방지).
개별 명령어(`tm`, `kx` 등)는 `aliases.zsh`를 source하면 alias로 복원되어 기존처럼 쓸 수 있다.
tmux/nvim 등 비인터랙티브 환경에서는 alias가 없으므로 `bb tm`처럼 호출한다.

환경변수를 바꾸는 도구(`wenv`, `assume`)는 자식 프로세스로 실행하면 부모 셸에 적용되지 않으므로,
셸 init이 `bb`를 함수로 감싸 현재 셸에서 자동 eval한다. 따라서 대화형 셸에서는
`bb wenv`/`wenv`, `bb assume`이 env를 적용한다. 비대화형/스크립트에서는
`eval "$(bb wenv <preset>)"` 또는 `eval "$(bb assume <profile>)"`로 쓴다.

```bash
bb                # 사용법 + 도구 목록
bb list           # 도구 목록
bb help kx        # 도구별 도움말 (= kx -h)
bb kx ctx         # 도구 실행 (= kx ctx)
bb setup          # 초기 설정 (= binbox-setup, 재실행 안전)
bb doctor         # = binbox-doctor
bb check          # = binbox-check
bb upgrade        # binbox 업데이트 (git pull --ff-only + 변경 로그)
bb <Tab>          # 자동완성 (zsh: 개별 명령 포함, bash: bb만)
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
| `gx br` | fzf 브랜치 전환 (최근 커밋 순, `-a`로 원격 포함) |
| `gx log` | fzf 커밋 탐색, Enter로 해시 출력 (다른 명령과 조합) |
| `gx root` | 저장소 루트 경로 출력 (`--cd`로 eval 이동) |

```bash
gx br                        # 브랜치 선택 (preview: 최근 로그)
gx log                       # 커밋 탐색 (preview: diff)
git rebase -i $(gx log)^     # 선택 커밋부터 rebase
cd $(gx root)                # 저장소 루트로 이동
```

### Kubernetes

| 명령어 | 설명 |
|--------|------|
| `kx ctx` / `kx ns` | context / namespace 전환 |
| `kx log` | pod 선택 → `logs -f` (다중 컨테이너 지원, `--tail`) |
| `kx exec` | pod 선택 → 셸 접속 (bash 없으면 sh) |
| `kx pf` | pod 선택 → port-forward (containerPort 자동 감지) |

```bash
kx ctx my-cluster          # 인자 주면 fzf 없이 직접 전환
kx log -n monitoring
kx exec
kx pf my-pod 9000:8080
```

### AWS

| 명령어 | 설명 |
|--------|------|
| `assume` | AWS SSO/role profile을 임시 credentials로 현재 셸에 적용 (`bb assume` 전용) |
| `assm` | 실행 중 EC2 선택 → SSM 세션 접속 / 포트포워딩 |
| `wenv` | 프리셋 기반 작업 환경 전환 — AWS profile/region + kube context/namespace |

```bash
bb assume lg-pak-ops       # AWS SSO/role profile → 임시 credentials export
bb assume current          # 현재 env/account 확인
bb assume unset            # AWS env 제거
assm                       # 인스턴스 선택 → 셸 접속
assm pf 8080               # 인스턴스 선택 → localhost:8080 → 인스턴스:8080
assm pf db.internal:5432 15432  # 인스턴스 경유 원격 호스트 포워딩 (RDS 등)
wenv                       # 프리셋 선택 → AWS_PROFILE/REGION + kube context/ns 일괄 전환
wenv new dev               # 프리셋 생성 (~/.config/binbox/wenv.d/dev)
```

wenv 프리셋 파일은 bash 문법으로 필요한 항목만 채운다 (비어 있으면 건너뜀):

```bash
# ~/.config/binbox/wenv.d/dev
AWS_PROFILE=my-dev
AWS_REGION=ap-northeast-2
KUBE_CONTEXT=dev-cluster
KUBE_NAMESPACE=default
# EXPORTS=(FOO=bar)        # 추가 export
```

### Terraform — tfx

terraform 워크플로우 통합 명령 (`tm`과 같은 단일 명령 + 서브커맨드 구조).

| 서브커맨드 | 설명 |
|--------|------|
| `tfx plan` | `terraform plan -out=tfplan` (인자 패스스루, AWS 계정 배너 표시) |
| `tfx sum` | plan 요약 (tree / stree / draw / md / json) |
| `tfx session [분]` | apply 세션 시작 — 계정 확인(뒷 4자리 입력) 후 N분간만 apply 허용 |
| `tfx apply` | 세션 유효 + 계정 일치 시에만 `terraform apply tfplan` |
| `tfx state` | state fzf 탐색 (preview: `state show`) + list / show / mv / rm |

```bash
tfx plan && tfx sum tree
tfx sum md plan-summary.md
tfx session 15       # 현재 AWS 계정 확인 → 15분 세션 시작
tfx apply            # 세션 유효 + 계정 일치 시에만 apply
tfx state            # fzf 탐색 → 선택 주소 출력 (조합용: terraform taint "$(tfx state)")
tfx state rm         # 다중 선택 → 확인 후 state에서 제거 (인프라는 유지)
```

plan 파일 apply는 terraform의 yes 확인이 생략되므로 apply 세션이 그 역할을 대신한다.
세션은 시작 시점의 AWS 계정(STS 기준)에 묶이며, apply 시점에 계정이 다르면 거부한다.

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
| `binbox-setup` | 초기 설정 자동화 (링크 + 셸 rc 등록, 멱등) |
| `binbox-doctor` | 의존성 점검 (core 누락만 실패, OS별 설치 힌트) |
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
tm dirs prune           # 존재하지 않는 경로 일괄 정리
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
- **새 도구는 `bb new <name>`으로 생성한다** — 프롤로그(lib/common.sh source)/usage/`-h`
  케이스가 채워진 템플릿이 `libexec/<name>`에 만들어지고, shellcheck·`bb list`·zsh 완성·
  alias에 자동 반영된다.
- 공통 함수(`die`, `need_cmd`, `fzf_pick`, `confirm`, `sanitize_session`)는 `lib/common.sh`,
  k8s 헬퍼(`k8s_pick_pod`, `k8s_pick_container`)는 `lib/k8s.sh`에 있다.

향후 계획은 [ROADMAP.md](ROADMAP.md) 참고.

## 요구 사항

`binbox-doctor`가 점검한다. core 누락만 실패로 처리하고 optional은 경고만 표시.

**Core**: docker, tmux, fzf, git, lsof(macOS 기본)

**Optional**:
- kubectl — kx, wenv
- terraform, tf-summarize — tfx
- aws cli, session-manager-plugin — assume, assm, wenv, tfx
- age, jq — assume, sec
- shellcheck, bats-core — 개발용
- ss/iproute2 — Linux portcheck (없으면 lsof 대체)
