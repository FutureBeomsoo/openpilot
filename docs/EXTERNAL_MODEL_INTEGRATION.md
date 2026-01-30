# External ModelV2 Integration for openpilot v0.9.4

## 개요

이 문서는 openpilot v0.9.4 (commit 68aba7c)에서 외부 모델 소스를 통해 `modelV2` 메시지를 수신하여 차량을 제어할 수 있도록 수정한 내용을 설명합니다.

### 목적

- openpilot의 기본 신경망 모델 대신 **외부 소스**에서 `modelV2` 데이터를 받아 사용
- 커스텀 모델, 시뮬레이션, 연구 목적으로 활용 가능

### 아키텍처

```
[테스트 시나리오]
external_modelv2_publisher.py (가짜 데이터 생성) → modelV2 → openpilot

[실제 사용 시나리오]
외부 모델 서버 → ZMQ → external_modeld.py (브릿지) → modelV2 → openpilot
```

---

## 수정된 파일

### 1. `common/params.cc`

`UseExternalModel` 파라미터 추가:

```cpp
{"UseExternalModel", PERSISTENT},
```

### 2. `selfdrive/modeld/modeld.cc`

외부 모델 모드 지원을 위한 수정:

```cpp
void run_model(ModelState &model, VisionIpcClient &vipc_client_main, VisionIpcClient &vipc_client_extra, bool main_wide_camera, bool use_extra_client) {
  Params params;

  // Check if external model mode is enabled (modelV2 published by external source)
  bool use_external_model = params.getBool("UseExternalModel");
  LOGW("External Model mode: %s", use_external_model ? "enabled" : "disabled");

  // messaging - only include modelV2 if NOT using external model
  PubMaster pm(use_external_model ? std::vector<const char*>{"cameraOdometry"}
                                   : std::vector<const char*>{"modelV2", "cameraOdometry"});
  // ...

  if (model_output != nullptr) {
    // Only publish modelV2 if NOT using external model
    if (!use_external_model) {
      model_publish(&model, pm, ...);
    }
    // Always publish cameraOdometry
    posenet_publish(pm, ...);
  }
}
```

**핵심 변경사항:**
- `UseExternalModel=true` 시 `PubMaster`에서 `modelV2` 제외 (소켓 충돌 방지)
- `modelV2` publish 조건부 실행
- `cameraOdometry`는 항상 publish (locationd/calibrationd에서 필요)

### 3. `selfdrive/ui/qt/offroad/settings.cc`

Developer Settings에 토글 스위치 추가:

```cpp
// Use External Model toggle
toggl = new ParamControl("UseExternalModel",
                         "Use External Model",
                         "When enabled, modelV2 will be received from external source instead of internal model. "
                         "Use this for custom models or external inference systems.",
                         "../assets/offroad/icon_calibration.png",
                         this);
addItem(toggl);
```

---

## 새로 추가된 파일

### 1. `tools/sim/external_modelv2_publisher.py`

테스트용 가짜 `modelV2` 데이터 생성기:

```bash
# 기본 실행 (직진)
python tools/sim/external_modelv2_publisher.py

# 키보드 제어 모드
python tools/sim/external_modelv2_publisher.py --keyboard
```

**키보드 제어:**
- ⬆️⬇️: 속도 증가/감소
- ⬅️➡️: 좌/우 lateral offset
- Space: 초기화
- q: 종료

**v0.9.4 특이사항:**
- `action` 필드 없음 (v0.10.3에서 추가됨)
- `position.y`를 통해 lateral 제어 (LateralPlanner가 lat_mpc로 curvature 계산)

### 2. `selfdrive/modeld/external_modeld.py`

외부 ZMQ 소스에서 `modelV2` 데이터를 수신하는 브릿지:

```bash
# 환경 변수 설정
export EXTERNAL_MODELV2_ADDR=tcp://localhost:5557
export EXTERNAL_MODELV2_TOPIC=modelV2

# 실행
python selfdrive/modeld/external_modeld.py
```

**기능:**
- ZMQ SUB 소켓으로 외부 데이터 수신
- JSON 형식의 modelV2 데이터를 capnp 메시지로 변환
- 연결 끊김 시 기본 데이터로 fallback

### 3. `activate_env.sh`

Docker 컨테이너 환경 활성화 스크립트:

```bash
#!/bin/bash
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PYENV_ROOT/shims:$PATH"
eval "$(pyenv init -)"

# Set display for GUI apps
export DISPLAY=${DISPLAY:-:0}
export QT_X11_NO_MITSHM=1
export XDG_RUNTIME_DIR=/tmp/runtime-root
mkdir -p $XDG_RUNTIME_DIR 2>/dev/null

# Git safe directory (allow all - for Docker dev environment)
git config --global --add safe.directory '*' 2>/dev/null

# Activate poetry virtual environment directly (no subshell)
source /home/pbs/openpilot_ws/openpilot_e2e/.venv/bin/activate

# Set PYTHONPATH for openpilot modules
export PYTHONPATH="/home/pbs/openpilot_ws/openpilot_e2e:$PYTHONPATH"

echo "Environment activated! (pyenv + poetry venv)"
```

**사용법:**
```bash
source activate_env.sh
```

### 4. `docker-dev.sh`

Docker 개발 환경 관리 스크립트:

```bash
# 컨테이너 시작
./docker-dev.sh run

# 실행 중인 컨테이너에 접속
./docker-dev.sh exec

# 컨테이너 중지
./docker-dev.sh stop
```

**기능:**
- GPU 지원 (`--gpus all`)
- X11 포워딩 (UI 실행 가능)
- 볼륨 마운트 (호스트 코드 동기화)

### 5. `reset_submodules.sh`

서브모듈 초기화 스크립트:

```bash
#!/bin/bash
sudo git submodule deinit -f --all
git submodule update --init --recursive
```

**사용 시점:**
- 브랜치 전환 시 서브모듈 충돌 발생 시
- 서브모듈 파일 손상 시

---

## v0.9.4 vs v0.10.3 ModelV2 스키마 차이

| 필드 | v0.9.4 | v0.10.3 |
|------|--------|---------|
| `action` (desiredCurvature, desiredAcceleration, shouldStop) | ❌ 없음 | ✅ 있음 |
| `meta.laneChangeState` | ❌ 없음 | ✅ 있음 |
| `meta.laneChangeDirection` | ❌ 없음 | ✅ 있음 |
| `disengagePredictions.gasPressProbs` | ❌ 없음 | ✅ 있음 |
| `disengagePredictions.brakePressProbs` | ❌ 없음 | ✅ 있음 |
| `temporalPose` | ✅ 활성 | DEPRECATED |
| `gpuExecutionTime` | ✅ 활성 | DEPRECATED |
| `navEnabled` | ✅ 활성 | DEPRECATED |
| `locationMonoTime` | ✅ 활성 | DEPRECATED |

### v0.9.4 ModelDataV2 스키마

```capnp
struct ModelDataV2 {
  frameId @0 :UInt32;
  frameIdExtra @20 :UInt32;
  frameAge @1 :UInt32;
  frameDropPerc @2 :Float32;
  timestampEof @3 :UInt64;
  modelExecutionTime @15 :Float32;
  gpuExecutionTime @17 :Float32;
  rawPredictions @16 :Data;

  position @4 :XYZTData;
  orientation @5 :XYZTData;
  velocity @6 :XYZTData;
  orientationRate @7 :XYZTData;
  acceleration @19 :XYZTData;

  laneLines @8 :List(XYZTData);
  laneLineProbs @9 :List(Float32);
  laneLineStds @13 :List(Float32);
  roadEdges @10 :List(XYZTData);
  roadEdgeStds @14 :List(Float32);

  leads @11 :List(LeadDataV2);
  leadsV3 @18 :List(LeadDataV3);

  meta @12 :MetaData;
  confidence @23 :ConfidenceClass;
  temporalPose @21 :Pose;
  navEnabled @22 :Bool;
  locationMonoTime @24 :UInt64;
}
```

---

## Docker 개발 환경 설정

### 1. 초기 설정 (최초 1회)

```bash
# 호스트에서
cd ~/openpilot_ws/openpilot_e2e

# Docker 컨테이너 시작
./docker-dev.sh run

# 컨테이너 안에서 - 초기 설정
tools/ubuntu_setup.sh

# Cython 호환성 문제 해결 (av 패키지)
pip install "cython<3.0" wheel
pip install av==10.0.0 --no-build-isolation

# 빌드
source activate_env.sh
scons -u -j$(nproc)

# 컨테이너 상태 저장 (호스트에서)
docker commit openpilot-dev openpilot-dev:configured
```

### 2. 일반 사용

```bash
# 호스트에서
./docker-dev.sh run

# 컨테이너 안에서
source activate_env.sh
```

### 3. OpenCL 설치 (GPU 사용 시)

```bash
apt-get update
apt-get install -y ocl-icd-libopencl1 nvidia-opencl-dev
clinfo  # 확인
```

---

## 사용 방법

### 테스트 워크플로우

```bash
# 1. Docker 컨테이너 시작
./docker-dev.sh run

# 2. 환경 활성화
source activate_env.sh

# 3. UseExternalModel 활성화
python -c "from common.params import Params; Params().put_bool('UseExternalModel', True)"

# 4. 터미널 1: openpilot 실행
cd tools/sim
./launch_openpilot.sh

# 5. 터미널 2 (호스트): CARLA 시뮬레이터
./start_carla.sh

# 6. 터미널 3: bridge
./bridge.py

# 7. 터미널 4: external_modelv2_publisher
python tools/sim/external_modelv2_publisher.py --keyboard
```

### UseExternalModel 파라미터 제어

```bash
# 활성화
python -c "from common.params import Params; Params().put_bool('UseExternalModel', True)"

# 비활성화
python -c "from common.params import Params; Params().put_bool('UseExternalModel', False)"

# 확인
python -c "from common.params import Params; print(Params().get_bool('UseExternalModel'))"
```

---

## 트러블슈팅

### 1. `ModuleNotFoundError: No module named 'cereal'`

```bash
export PYTHONPATH="/home/pbs/openpilot_ws/openpilot_e2e:$PYTHONPATH"
# 또는
source activate_env.sh
```

### 2. `MultiplePublishersError: Address already in use`

- `UseExternalModel`이 활성화되어 있는지 확인
- openpilot 재시작 (modeld가 파라미터를 시작 시점에 읽음)

```bash
pkill -9 -f modeld
./launch_openpilot.sh
```

### 3. `clGetPlatformIDs failed: PLATFORM_NOT_FOUND_KHR`

```bash
# OpenCL 라이브러리 설치
apt-get install -y ocl-icd-libopencl1 nvidia-opencl-dev

# 또는 컨테이너를 --gpus all 옵션으로 재시작
./docker-dev.sh stop
./docker-dev.sh run
```

### 4. Git `dubious ownership` 경고

```bash
git config --global --add safe.directory '*'
```

### 5. 서브모듈 충돌

```bash
./reset_submodules.sh
```

### 6. numpy.float64 capnp 오류

capnp는 numpy 타입을 지원하지 않음. Python native float로 변환 필요:
```python
# 잘못된 예
positions_x = [v_ego * t for t in T_IDXS]  # numpy.float64

# 올바른 예
positions_x = [float(v_ego * t) for t in T_IDXS]  # Python float
```

### 7. "Low Communication Rate between Processes" 오류 (해결됨)

외부 모델이 20Hz로 정확히 publish하지 않을 때 발생했던 오류입니다.

**원인:**
- openpilot은 modelV2가 20Hz로 도착하는지 체크
- 외부 모델의 publish 주기가 불규칙하면 `commIssueAvgFreq` 이벤트 발생
- 이로 인해 "openpilot Unavailable" 상태가 됨

**해결:**
`controlsd.py`와 `plannerd.py`에서 modelV2의 주파수 체크를 비활성화:

```python
# selfdrive/controls/controlsd.py:89
ignore_avg_freq=['radarState', 'testJoystick', 'modelV2']

# selfdrive/controls/plannerd.py:46
ignore_avg_freq=['radarState', 'modelV2']
```

**영향받는 프로세스:**
| 프로세스 | 역할 | modelV2 사용 |
|----------|------|--------------|
| controlsd | 메인 제어 | 주파수 체크, 상태 모니터링 |
| plannerd | 경로 계획 | lateral/longitudinal plan 생성 |
| radard | 레이더 처리 | 이미 ignore_avg_freq에 포함됨 |

---

## Git 커밋 히스토리

```
418d4d147 fix: ignore modelV2 frequency check for external model mode
035e5183c fix: conditionally create PubMaster based on UseExternalModel
7f4b45353 fix: convert numpy types to Python floats for capnp
f592854eb fix: add PYTHONPATH for openpilot modules
fbd306e81 refactor: use wildcard for git safe.directory
0ede817ee fix: add all submodules to git safe.directory
1b878e093 fix: make activate_env.sh manual instead of auto-run
178fd7492 refactor: use git submodule deinit instead of rm -rf
f6aa8b11c feat: add reset_submodules.sh for branch switching
20f72cf30 feat: add environment activation script for Docker
e5cf4277f feat: add external_modelv2_publisher.py for v0.9.4 testing
f9ecdd262 chore: update docker-dev.sh to use pre-configured image
```

---

## 파일 구조

```
openpilot/
├── activate_env.sh                    # 환경 활성화 스크립트
├── docker-dev.sh                      # Docker 관리 스크립트
├── reset_submodules.sh                # 서브모듈 초기화 스크립트
├── common/
│   └── params.cc                      # UseExternalModel 파라미터 추가
├── selfdrive/
│   ├── controls/
│   │   ├── controlsd.py               # modelV2 주파수 체크 비활성화
│   │   └── plannerd.py                # modelV2 주파수 체크 비활성화
│   ├── modeld/
│   │   ├── modeld.cc                  # 외부 모델 모드 지원
│   │   └── external_modeld.py         # ZMQ 브릿지
│   └── ui/qt/offroad/
│       └── settings.cc                # UI 토글 추가
├── tools/
│   └── sim/
│       └── external_modelv2_publisher.py  # 테스트용 publisher
└── docs/
    └── EXTERNAL_MODEL_INTEGRATION.md  # 이 문서
```

---

## 라이선스

MIT License - comma.ai openpilot

## 참고

- openpilot v0.9.4: https://github.com/commaai/openpilot/tree/v0.9.4
- CARLA Simulator: https://carla.org/
