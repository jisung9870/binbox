# binbox

개인 CLI 스크립트 모음. Mac / WSL 환경에서 `$PATH`에 등록해 사용한다.

```bash
# .zshrc
export PATH="$HOME/binbox:$PATH"
```

## 구조

```
binbox/
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
├── tmux-layouts/           # tmux 레이아웃 정의
│   ├── golang-layout
│   ├── k8s-layout
│   └── terraform-layout
├── kctx                    # fzf 기반 kubectl context 전환
├── kns                     # fzf 기반 kubectl namespace 전환
├── portcheck               # 포트 사용 프로세스 확인
└── gitroot                 # git 저장소 루트로 cd
```

## dx — Docker 기반 도구 실행기

호스트에 도구를 설치하지 않고 Docker 컨테이너로 실행한다. `dx.d/` 디렉토리에 설정 파일을 추가하면 자동으로 사용 가능.

```bash
# 사용 가능한 도구 목록
dx

# ansible 실행
dx ansible ansible-playbook site.yml

# 컨테이너 안에서 bash 접근
dx ubuntu

# terraform plan
dx terraform plan

# golang 개발
dx golang go test ./...
```

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

```bash
# 프로젝트 선택 → 세션 생성
tmux-sessionizer

# 레이아웃 선택 → 세션 생성
tmux-layout my-project ~/home/projects/my-project

# k8s 패턴 세션 일괄 삭제
tmux-kill-pattern k8s
```

### 레이아웃 추가

`tmux-layouts/` 디렉토리에 `*-layout` 파일을 추가한다. `tmux-layout` 명령어가 자동으로 인식한다.

## Kubernetes 유틸리티

```bash
# context 전환 (fzf)
kctx

# namespace 전환 (fzf)
kns

# 특정 context/namespace 직접 지정
kctx my-cluster
kns monitoring
```

## 기타 유틸리티

```bash
# 포트 사용 프로세스 확인
portcheck 8080

# git 저장소 루트로 이동
cd $(gitroot)
# 또는 eval로 직접 이동
eval "$(gitroot --cd)"
```

## 요구 사항

- Docker
- tmux
- fzf (`brew install fzf`)
- kubectl (kctx, kns 사용 시)

## 설치

```bash
git clone https://github.com/<your-username>/binbox.git ~/binbox

# .zshrc에 추가
echo 'export PATH="$HOME/binbox:$PATH"' >> ~/.zshrc
source ~/.zshrc

# 실행 권한 부여
chmod +x ~/binbox/*
chmod +x ~/binbox/tmux-layouts/*
```
