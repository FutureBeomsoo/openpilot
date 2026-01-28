# openpilot v0.9.4 Docker 빌드 가이드

이 문서는 openpilot v0.9.4를 Docker 환경에서 빌드하고 실행하는 방법을 설명합니다.

---

## 목차

1. [개요](#개요)
2. [사전 요구사항](#사전-요구사항)
3. [Docker 이미지 구조](#docker-이미지-구조)
4. [빌드 방법](#빌드-방법)
5. [실행 방법](#실행-방법)
6. [문제 해결](#문제-해결)
7. [다른 버전 적용 가이드](#다른-버전-적용-가이드)

---

## 개요

### 왜 Docker를 사용하는가?

- **환경 일관성**: 어떤 PC에서든 동일한 개발/테스트 환경 구축 가능
- **의존성 관리**: 시스템 패키지와 Python 패키지 버전 고정
- **재현성**: 언제든 동일한 환경을 다시 구축 가능

### Dockerfile 구조

```
Dockerfile.v094.base  → 베이스 이미지 (시스템 패키지 + Python 환경)
Dockerfile.v094       → 빌드 이미지 (소스 코드 복사 + scons 빌드)
```

이렇게 분리한 이유:
- 베이스 이미지는 한 번만 빌드하면 됨 (시간 절약)
- 소스 코드 수정 시 빌드 이미지만 재빌드

---

## 사전 요구사항

### 시스템 요구사항

| 항목 | 최소 사양 | 권장 사양 |
|------|----------|----------|
| OS | Ubuntu 20.04+ / WSL2 | Ubuntu 20.04 |
| RAM | 8GB | 16GB+ |
| 저장공간 | 30GB | 50GB+ |
| CPU | 4코어 | 8코어+ |

### Docker 설치

#### Ubuntu
```bash
# Docker 설치
curl -fsSL https://get.docker.com | sh

# 현재 사용자를 docker 그룹에 추가 (sudo 없이 사용)
sudo usermod -aG docker $USER

# 로그아웃 후 다시 로그인하여 그룹 변경 적용
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
    └── Python 패키지 설치
        ├── numpy==1.23.0
        ├── protobuf==3.20.3
        ├── casadi==3.6.3
        └── 기타 의존성...
```

### Dockerfile.v094 (빌드 이미지)

```
openpilot-base:v094
    │
    ├── 소스 코드 복사
    │   ├── SConstruct
    │   ├── third_party/
    │   ├── cereal/, opendbc/, panda/
    │   ├── selfdrive/, system/
    │   └── tools/, scripts/
    │
    └── scons 빌드 실행
```

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

**예상 소요 시간**: 10-20분 (인터넷 속도 및 시스템 사양에 따라 다름)

**주요 과정**:
1. Ubuntu 20.04 베이스 이미지 다운로드
2. 시스템 패키지 설치 (apt-get)
3. pyenv로 Python 3.11.4 빌드 및 설치
4. pip로 Python 패키지 설치

### 3단계: 빌드 이미지 생성

```bash
docker build -t openpilot:v094 -f Dockerfile.v094 .
```

**예상 소요 시간**: 5-10분

**주요 과정**:
1. 소스 코드 복사
2. scons로 C++ 코드 컴파일
3. Cython 확장 모듈 빌드

### 빌드 옵션

```bash
# 빌드 캐시 없이 처음부터 빌드
docker build --no-cache -t openpilot-base:v094 -f Dockerfile.v094.base .

# 병렬 빌드 코어 수 조절 (메모리 부족 시)
# Dockerfile.v094에서 scons -j$(nproc) 대신 scons -j4 등으로 수정
```

---

## 실행 방법

### 컨테이너 실행

```bash
# 대화형 쉘로 실행
docker run -it --rm openpilot:v094 bash

# 호스트 디렉토리 마운트하여 실행 (개발용)
docker run -it --rm \
    -v $(pwd):/root/openpilot \
    openpilot:v094 bash
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
    -e DISPLAY=$DISPLAY \
    -v /tmp/.X11-unix:/tmp/.X11-unix \
    openpilot:v094 bash
```

---

## 문제 해결

### 빌드 실패: 메모리 부족

**증상**: 빌드 중 프로세스가 killed 되거나 시스템이 느려짐

**해결**:
```bash
# 병렬 빌드 코어 수 줄이기
# Dockerfile.v094에서:
RUN /tmp/openpilot/.venv/bin/scons -j4  # 또는 -j2
```

### 빌드 실패: 패키지를 찾을 수 없음

**증상**: `ModuleNotFoundError: No module named 'xxx'`

**해결**:
```bash
# Dockerfile.v094.base의 pip install 라인에 패키지 추가
RUN pip install ... 새패키지명
```

### 빌드 실패: numpy 버전 문제

**증상**: `ValueError: operands could not be broadcast together`

**해결**: numpy 버전이 1.23.0인지 확인
```bash
# Dockerfile.v094.base에서
RUN pip install numpy==1.23.0
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
├── Dockerfile.v094.base    # 베이스 이미지 정의
├── Dockerfile.v094         # 빌드 이미지 정의
├── docs/
│   └── DOCKER_BUILD_KR.md  # 이 문서
├── pyproject.toml          # Python 의존성 정의
├── .python-version         # Python 버전 (3.11.4)
├── SConstruct              # 빌드 설정
└── tools/
    └── ubuntu_setup.sh     # 시스템 패키지 목록 참조
```

---

## 참고 자료

- [openpilot GitHub](https://github.com/commaai/openpilot)
- [comma.ai 문서](https://docs.comma.ai)
- [Docker 공식 문서](https://docs.docker.com)

---

## 변경 이력

| 날짜 | 변경 내용 |
|------|----------|
| 2024-01 | 최초 작성 (v0.9.4 기준) |
