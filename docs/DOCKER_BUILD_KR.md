# openpilot v0.9.4 Docker 빌드 가이드

이 문서는 openpilot v0.9.4를 Docker 환경에서 빌드하고 실행하는 방법을 설명합니다.

---

## 목차

1. [개요](#개요)
2. [사전 요구사항](#사전-요구사항)
3. [Docker 이미지 구조](#docker-이미지-구조)
4. [빌드 방법](#빌드-방법)
5. [실행 방법](#실행-방법)
6. [개발 환경 설정](#개발-환경-설정)
7. [시뮬레이터 실행](#시뮬레이터-실행)
8. [문제 해결](#문제-해결)
9. [다른 버전 적용 가이드](#다른-버전-적용-가이드)

---

## 개요

### 왜 Docker를 사용하는가?

- **환경 일관성**: 어떤 PC에서든 동일한 개발/테스트 환경 구축 가능
- **의존성 관리**: 시스템 패키지와 Python 패키지 버전 고정
- **재현성**: 언제든 동일한 환경을 다시 구축 가능

### Dockerfile 구조

```
Dockerfile.v094.base      → 베이스 이미지 (시스템 패키지 + Python 환경)
    │
    ├── Dockerfile.v094.base.cl  → OpenCL 지원 추가
    │       │
    │       └── Dockerfile.v094.sim  → 시뮬레이터 이미지 (CARLA + 빌드)
    │
    └── Dockerfile.v094      → 기본 빌드 이미지 (소스 코드 + 빌드)
```

이렇게 분리한 이유:
- 베이스 이미지는 한 번만 빌드하면 됨 (시간 절약)
- 소스 코드 수정 시 빌드 이미지만 재빌드
- 시뮬레이터가 필요 없으면 base.cl, sim 생략 가능

---

## 사전 요구사항

### 시스템 요구사항

| 항목 | 최소 사양 | 권장 사양 |
|------|----------|----------|
| OS | Ubuntu 20.04+ / WSL2 | Ubuntu 20.04 |
| RAM | 8GB | 16GB+ |
| 저장공간 | 30GB | 50GB+ |
| CPU | 4코어 | 8코어+ |
| GPU | - | NVIDIA (시뮬레이터용) |

### Docker 설치

#### Ubuntu
```bash
# Docker 설치
curl -fsSL https://get.docker.com | sh

# 현재 사용자를 docker 그룹에 추가 (sudo 없이 사용)
sudo usermod -aG docker $USER

# 로그아웃 후 다시 로그인하여 그룹 변경 적용
```

#### GPU 지원 (NVIDIA)
```bash
# NVIDIA Container Toolkit 설치
distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | sudo apt-key add -
curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | sudo tee /etc/apt/sources.list.d/nvidia-docker.list

sudo apt-get update
sudo apt-get install -y nvidia-container-toolkit
sudo systemctl restart docker
```

#### Windows (WSL2)
1. [Docker Desktop](https://www.docker.com/products/docker-desktop/) 설치
2. WSL2 백엔드 활성화
3. Ubuntu 배포판 설치

### Git LFS 설치

openpilot은 대용량 파일을 Git LFS로 관리합니다.

```bash
# Ubuntu
sudo apt-get install git-lfs
git lfs install

# 저장소에서 LFS 파일 가져오기
cd openpilot
git lfs pull
```

---

## Docker 이미지 구조

### Dockerfile.v094.base (베이스 이미지)

`tools/ubuntu_setup.sh`와 동일한 역할을 수행합니다.

```
ubuntu:20.04
    │
    ├── 시스템 패키지 설치
    │   ├── 빌드 도구 (gcc, clang, cmake, scons)
    │   ├── 라이브러리 (OpenCV, Qt5, FFmpeg, OpenCL)
    │   ├── Cap'n Proto
    │   └── gcc-arm-none-eabi (panda 펌웨어용)
    │
    ├── pyenv + Python 3.11.4 설치
    │
    └── /tmp/openpilot/.venv (가상환경)
        ├── numpy==1.23.0
        ├── protobuf==3.20.3
        ├── casadi==3.6.3
        └── 기타 의존성...
```

### Dockerfile.v094.base.cl (OpenCL 이미지)

```
openpilot-base:v094
    │
    ├── Intel OpenCL 드라이버
    ├── NVIDIA 환경 변수 설정
    └── tmux (멀티 터미널용)
```

### Dockerfile.v094.sim (시뮬레이터 이미지)

```
openpilot-base-cl:v094
    │
    ├── Python 패키지 추가
    │   ├── pygame
    │   ├── opencv-python-headless
    │   └── carla==0.9.14
    │
    ├── 소스 코드 복사 → /root/openpilot
    │
    └── scons 빌드 실행
```

### 로컬 환경과의 비교

| 로컬 환경 (tools/README.md) | Docker 환경 |
|----------------------------|-------------|
| `tools/ubuntu_setup.sh` | `Dockerfile.v094.base` |
| `cd openpilot && poetry shell` | ENV PATH로 자동 활성화 |
| `scons -j$(nproc)` | Dockerfile에서 자동 빌드 |

---

## 빌드 방법

### 1단계: 저장소 클론 및 준비

```bash
# 저장소 클론
git clone https://github.com/commaai/openpilot.git
cd openpilot

# v0.9.4 태그로 체크아웃 (필요한 경우)
git checkout v0.9.4

# Git LFS 파일 가져오기
git lfs pull

# 서브모듈 초기화
git submodule update --init
```

### 2단계: 베이스 이미지 빌드

```bash
docker build -t openpilot-base:v094 -f Dockerfile.v094.base .
```

**예상 소요 시간**: 10-20분

### 3단계: 목적에 맞는 이미지 선택

#### 옵션 A: 기본 빌드만 필요한 경우

```bash
docker build -t openpilot:v094 -f Dockerfile.v094 .
```

#### 옵션 B: 시뮬레이터가 필요한 경우

```bash
# OpenCL 이미지 빌드
docker build -t openpilot-base-cl:v094 -f Dockerfile.v094.base.cl .

# 시뮬레이터 이미지 빌드
docker build -t openpilot-sim:v094 -f Dockerfile.v094.sim .
```

### 빌드 옵션

```bash
# 빌드 캐시 없이 처음부터 빌드
docker build --no-cache -t openpilot-base:v094 -f Dockerfile.v094.base .

# 병렬 빌드 코어 수 조절 (메모리 부족 시)
# Dockerfile에서 scons -j$(nproc) 대신 scons -j4 등으로 수정
```

---

## 실행 방법

### 기본 컨테이너 실행

```bash
# 대화형 쉘로 실행
docker run -it --rm openpilot:v094 bash

# 시뮬레이터 이미지 실행 (GPU 지원)
docker run -it --rm --gpus all openpilot-sim:v094 bash
```

### 컨테이너 내부에서 테스트

```bash
# Python import 테스트
python -c "import cereal; print('cereal OK')"
python -c "import selfdrive; print('selfdrive OK')"

# 특정 모듈 테스트
cd /root/openpilot
python selfdrive/test/test_params.py
```

### GUI 애플리케이션 실행 (X11 포워딩)

```bash
# 호스트에서 X11 연결 허용
xhost +local:docker

# GUI 지원으로 컨테이너 실행
docker run -it --rm \
    --gpus all \
    -e DISPLAY=$DISPLAY \
    -v /tmp/.X11-unix:/tmp/.X11-unix \
    openpilot-sim:v094 bash
```

---

## 개발 환경 설정

### 로컬 코드 마운트 실행

로컬에서 코드를 수정하고, Docker 컨테이너에서 빌드/테스트하는 워크플로우입니다.

```bash
docker run -it --rm --gpus all \
    -e DISPLAY=$DISPLAY \
    -v /tmp/.X11-unix:/tmp/.X11-unix \
    -v $(pwd):/root/openpilot \
    --network host \
    openpilot-sim:v094 /bin/bash
```

**주요 옵션 설명**:
- `-v $(pwd):/root/openpilot`: 현재 디렉토리를 컨테이너에 마운트
- `--network host`: 호스트 네트워크 공유 (CARLA 연결용)
- `--gpus all`: GPU 사용

### 마운트 시 빌드

로컬 코드를 마운트하면 이미지의 빌드 결과물이 덮어씌워지므로, 컨테이너 내부에서 다시 빌드해야 합니다:

```bash
# 컨테이너 내부에서
scons -j$(nproc)
```

또는 한 번에:

```bash
docker run -it --rm --gpus all \
    -e DISPLAY=$DISPLAY \
    -v /tmp/.X11-unix:/tmp/.X11-unix \
    -v $(pwd):/root/openpilot \
    --network host \
    openpilot-sim:v094 \
    bash -c "scons -j\$(nproc) && /bin/bash"
```

### 개발용 스크립트

`tools/sim/run_dev_docker.sh` 스크립트를 사용하면 편리합니다:

```bash
cd tools/sim
./run_dev_docker.sh
```

### 가상환경 구조

```
Docker 내부 구조:
├── /tmp/openpilot/.venv/     ← Python 환경 (이미지에 포함, 유지됨)
└── /root/openpilot/          ← 소스 코드 (여기에 로컬 마운트)
```

- 가상환경은 `/tmp/openpilot/.venv`에 위치
- 소스 코드는 `/root/openpilot`에 마운트
- 두 경로가 분리되어 있어 로컬 코드 마운트해도 가상환경 유지

### 가상환경 비활성화 (필요시)

```bash
# 시스템 Python 직접 사용
/usr/bin/python3 script.py

# 또는 컨테이너 내부에서
unset VIRTUAL_ENV
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
```

---

## 시뮬레이터 실행

### CARLA 시뮬레이터 설치

```bash
# CARLA Docker 이미지 (호스트에서)
docker pull carlasim/carla:0.9.13
```

### 시뮬레이터 실행 방법

**Terminal 1: CARLA 시뮬레이터**
```bash
cd tools/sim
./start_carla.sh
```

**Terminal 2: openpilot**
```bash
cd tools/sim
./start_openpilot_docker_v094.sh
```

### 시뮬레이터 스크립트

| 스크립트 | 설명 |
|---------|------|
| `tools/sim/start_carla.sh` | CARLA 시뮬레이터 실행 |
| `tools/sim/start_openpilot_docker_v094.sh` | openpilot 시뮬레이터 연결 |
| `tools/sim/run_dev_docker.sh` | 개발용 (로컬 코드 마운트 + 빌드) |

### 시뮬레이터 테스트

```bash
# 컨테이너 내부에서
cd /root/openpilot/tools/sim
python bridge.py
```

---

## 문제 해결

### 빌드 실패: 메모리 부족

**증상**: 빌드 중 프로세스가 killed 되거나 시스템이 느려짐

**해결**:
```bash
# 병렬 빌드 코어 수 줄이기
# Dockerfile에서:
RUN /tmp/openpilot/.venv/bin/scons -j4  # 또는 -j2
```

### 빌드 실패: numpy 버전 문제

**증상**: `ValueError: operands could not be broadcast together`

**원인**: numpy 버전이 acados와 호환되지 않음

**해결**: numpy 버전이 1.23.0인지 확인
```bash
# Dockerfile.v094.base에서
RUN pip install numpy==1.23.0
```

### 빌드 실패: 패키지를 찾을 수 없음

**증상**: `ModuleNotFoundError: No module named 'xxx'`

**해결**:
```bash
# Dockerfile.v094.base의 pip install 라인에 패키지 추가
RUN pip install ... 새패키지명
```

### Docker 빌드 캐시 문제

**증상**: 변경사항이 반영되지 않음

**해결**:
```bash
# 캐시 없이 재빌드
docker build --no-cache -t openpilot-base:v094 -f Dockerfile.v094.base .
```

### av 패키지 설치 오류

**증상**: Cython 3.0 호환성 문제로 av 빌드 실패

**해결**: 컨테이너 내에서 수동 설치
```bash
docker run -it openpilot:v094 bash
pip install 'Cython<3.0'
pip install --no-build-isolation av==9.2.0
```

### GPU가 인식되지 않음

**증상**: `docker: Error response from daemon: could not select device driver`

**해결**: NVIDIA Container Toolkit 설치
```bash
sudo apt-get install -y nvidia-container-toolkit
sudo systemctl restart docker
```

### X11 디스플레이 오류

**증상**: `cannot open display`

**해결**:
```bash
# 호스트에서 실행
xhost +local:docker
```

---

## 다른 버전 적용 가이드

### 새로운 openpilot 버전에 Docker 환경 구축하기

#### 1. 버전 정보 확인

```bash
# Python 버전 확인
cat .python-version

# 의존성 확인
cat pyproject.toml
```

#### 2. Dockerfile.base 수정

1. **Python 버전 변경** (필요한 경우):
```dockerfile
ENV PYENV_VERSION=3.11.4  # 새 버전으로 변경
```

2. **시스템 패키지 확인**:
   - `tools/ubuntu_setup.sh` 참조
   - 새로 필요한 패키지 추가

3. **Python 패키지 버전 확인**:
```bash
# pyproject.toml에서 버전이 고정된 패키지 확인
grep "==" pyproject.toml
```

#### 3. 버전 호환성 체크리스트

| 항목 | 확인 방법 |
|------|----------|
| Python 버전 | `.python-version` 파일 |
| numpy 버전 | `pyproject.toml` (acados 호환성) |
| protobuf 버전 | `pyproject.toml` |
| casadi 버전 | `pyproject.toml` |
| 시스템 패키지 | `tools/ubuntu_setup.sh` |

#### 4. 테스트

```bash
# 베이스 이미지 빌드
docker build -t openpilot-base:NEW_VERSION -f Dockerfile.NEW_VERSION.base .

# 빌드 이미지 생성
docker build -t openpilot:NEW_VERSION -f Dockerfile.NEW_VERSION .

# 컨테이너 실행 및 테스트
docker run -it --rm openpilot:NEW_VERSION bash
python -c "import selfdrive"
```

---

## 파일 구조 요약

```
openpilot/
├── Dockerfile.v094.base       # 베이스 이미지 (환경 설정)
├── Dockerfile.v094.base.cl    # OpenCL 추가 이미지
├── Dockerfile.v094.sim        # 시뮬레이터 이미지 (빌드 포함)
├── Dockerfile.v094            # 기본 빌드 이미지
├── docs/
│   └── DOCKER_BUILD_KR.md     # 이 문서
├── tools/
│   ├── sim/
│   │   ├── start_carla.sh              # CARLA 실행
│   │   ├── start_openpilot_docker_v094.sh  # 시뮬레이터 실행
│   │   └── run_dev_docker.sh           # 개발용 Docker 실행
│   ├── ubuntu_setup.sh        # (참조용) 시스템 패키지 목록
│   └── README.md              # tools 설명
├── pyproject.toml             # Python 의존성 정의
├── .python-version            # Python 버전 (3.11.4)
└── SConstruct                 # 빌드 설정
```

---

## 빠른 시작 요약

### 처음 빌드

```bash
# 1. 저장소 준비
git clone https://github.com/commaai/openpilot.git
cd openpilot
git lfs pull
git submodule update --init

# 2. 이미지 빌드 (순서대로)
docker build -t openpilot-base:v094 -f Dockerfile.v094.base .
docker build -t openpilot-base-cl:v094 -f Dockerfile.v094.base.cl .
docker build -t openpilot-sim:v094 -f Dockerfile.v094.sim .
```

### 개발 시작

```bash
# 로컬 코드로 개발
cd tools/sim
./run_dev_docker.sh
```

### 시뮬레이터 테스트

```bash
# Terminal 1
cd tools/sim && ./start_carla.sh

# Terminal 2
cd tools/sim && ./start_openpilot_docker_v094.sh
```

---

## 참고 자료

- [openpilot GitHub](https://github.com/commaai/openpilot)
- [comma.ai 문서](https://docs.comma.ai)
- [Docker 공식 문서](https://docs.docker.com)
- [CARLA Simulator](https://carla.org/)

---

## 변경 이력

| 날짜 | 변경 내용 |
|------|----------|
| 2024-01 | 최초 작성 (v0.9.4 기준) |
| 2024-01 | 시뮬레이터 환경 추가 (Dockerfile.v094.base.cl, Dockerfile.v094.sim) |
| 2024-01 | 개발 환경 설정 섹션 추가 |
