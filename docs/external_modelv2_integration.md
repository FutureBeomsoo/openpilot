# External ModelV2 Integration for v0.9.4

openpilot v0.9.4 (68aba7c)에서 내부 modeld 대신 외부 소스로부터 modelV2 메시지를 받아 차량을 제어할 수 있도록 하는 기능 구현 문서

## v0.9.4 vs v0.10.3 아키텍처 차이

### v0.10.3 (참고)
- modeld가 Python으로 구현
- ModelV2.action.desiredCurvature를 직접 계산하여 제공
- controlsd에서 action.desiredCurvature를 직접 사용

### v0.9.4 (현재 구현)
- modeld가 C++로 구현
- ModelV2에 action 필드가 없음
- LateralPlanner가 trajectory 데이터에서 lat_mpc를 통해 curvature 계산
- controlsd에서 lateralPlan.curvatures를 사용

## 메시지 흐름

### 기존 (native modeld)
```
camerad → modeld.cc → modelV2 → LateralPlanner → lateralPlan → controlsd → 차량
                    → cameraOdometry → locationd/calibrationd
```

### External Model 모드
```
외부 시스템 (ZMQ) → external_modeld.py → modelV2 → LateralPlanner → lateralPlan → controlsd → 차량
                                       → cameraOdometry → locationd/calibrationd
```

## 구현 상세

### 1. 파라미터 추가 (`common/params.cc`)

```cpp
// External Model Parameters
{"UseExternalModel", PERSISTENT},
{"ExternalModelV2Addr", PERSISTENT},
{"ExternalModelV2Topic", PERSISTENT},
```

### 2. 프로세스 설정 (`selfdrive/manager/process_config.py`)

```python
def use_external_model(started, params, CP: car.CarParams) -> bool:
  """Check if external model should be used instead of native modeld"""
  return started and params.get_bool("UseExternalModel")

def use_native_model(started, params, CP: car.CarParams) -> bool:
  """Check if native modeld should be used (not external)"""
  return started and not params.get_bool("UseExternalModel")

procs = [
  # ...
  NativeProcess("modeld", "selfdrive/modeld", ["./modeld"], callback=use_native_model),
  PythonProcess("external_modeld", "selfdrive.modeld.external_modeld", callback=use_external_model),
  # ...
]
```

### 3. External ModelV2 Receiver (`selfdrive/modeld/external_modeld.py`)

ZMQ를 통해 외부에서 JSON 형식의 ModelV2 데이터를 수신하고 openpilot 내부 메시지로 변환하여 발행합니다.

## 사용 방법

### 1. External Model 활성화

```bash
# PC에서
echo -n "1" > ~/.comma/params/d/UseExternalModel

# 디바이스에서
echo -n "1" > /data/params/d/UseExternalModel
```

### 2. 선택적: ZMQ 주소/토픽 설정

```bash
echo -n "tcp://192.168.1.100:5557" > ~/.comma/params/d/ExternalModelV2Addr
echo -n "modelV2" > ~/.comma/params/d/ExternalModelV2Topic
```

기본값:
- 주소: `tcp://localhost:5557`
- 토픽: `modelV2`

### 3. 외부 시스템에서 데이터 발행

```python
import zmq
import json
import time

context = zmq.Context()
socket = context.socket(zmq.PUB)
socket.bind("tcp://*:5557")

while True:
    data = {
        "position": {
            "x": [0.0, 0.31, 1.25, ...],  # 33 points
            "y": [0.0, 0.0, ...],
            "z": [0.0, 0.0, ...],
            "t": [0.0, 0.1, 0.39, ...]
        },
        "orientation": {
            "x": [0.0] * 33,
            "y": [0.0] * 33,
            "z": [0.0] * 33  # yaw angles
        },
        "orientationRate": {
            "x": [0.0] * 33,
            "y": [0.0] * 33,
            "z": [0.0] * 33  # yaw rates
        },
        "velocity": {
            "x": [10.0] * 33,  # forward velocity
            "y": [0.0] * 33,
            "z": [0.0] * 33
        },
        "meta": {
            "desireState": [1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
        }
    }
    socket.send_string("modelV2", zmq.SNDMORE)
    socket.send_string(json.dumps(data))
    time.sleep(0.05)  # 20 Hz
```

## ModelV2 데이터 필드 상세

### 필수 필드 (LateralPlanner가 사용)

| 필드 | 형식 | 설명 |
|------|------|------|
| position.x | float[33] | 전방 예측 위치 (m) |
| position.y | float[33] | 횡방향 예측 위치 (m) |
| position.z | float[33] | 수직 예측 위치 (m) |
| position.t | float[33] | 시간 인덱스 (s) |
| orientation.z | float[33] | 예측 yaw 각도 (rad) |
| orientationRate.z | float[33] | 예측 yaw 속도 (rad/s) |
| velocity.x/y/z | float[33] | 예측 속도 (m/s) |
| meta.desireState | float[8] | 차선 변경 의도 확률 |

### 시간 인덱스 (T_IDXS)

33개 포인트, 0~10초 사이 2차 함수 분포:
```
[0.0, 0.00976563, 0.0390625, 0.0878906, 0.15625, 0.244141, 0.351563, 0.478516,
 0.625, 0.791016, 0.976563, 1.18164, 1.40625, 1.65039, 1.91406, 2.19727,
 2.5, 2.82227, 3.16406, 3.52539, 3.90625, 4.30664, 4.72656, 5.16602,
 5.625, 6.10352, 6.60156, 7.11914, 7.65625, 8.21289, 8.78906, 9.38477, 10.0]
```

### 선택적 필드

| 필드 | 형식 | 설명 |
|------|------|------|
| laneLines | XYZTData[4] | 차선 예측 |
| laneLineProbs | float[4] | 차선 감지 확률 |
| roadEdges | XYZTData[2] | 도로 경계 예측 |
| leadsV3 | LeadDataV3[3] | 선행 차량 예측 |
| meta.engagedProb | float | 주행 활성 확률 |
| meta.hardBrakePredicted | bool | 급제동 예측 |
| temporalPose | Pose | 시간적 위치 추정 |
| confidence | string | 신뢰도 (green/yellow/red) |

## 기술 참고사항

### LateralPlanner 동작 방식

1. ModelV2에서 trajectory 데이터 추출:
   - `md.position.x/y/z` → `path_xyz`
   - `md.position.t` → `t_idxs`
   - `md.orientation.z` → `plan_yaw`
   - `md.orientationRate.z` → `plan_yaw_rate`
   - `md.velocity.x/y/z` → `velocity_xyz` → `v_plan`

2. lat_mpc 실행하여 curvature 계산:
   ```python
   self.lat_mpc.run(self.x0, p, y_pts, heading_pts, yaw_rate_pts)
   ```

3. lateralPlan 메시지로 발행:
   - `lateralPlan.curvatures`
   - `lateralPlan.curvatureRates`

### capnp 메시지 생성 주의사항

```python
# 올바른 방법: init()으로 리스트 초기화
lane_lines = model.init('laneLines', 4)
for i in range(4):
    fill_xyzt_data(lane_lines[i], lane_data[i])

# 잘못된 방법: add() 사용
# lane_line = model.laneLines.add()  # AttributeError 발생
```

### valid 플래그 설정

```python
msg = messaging.new_message('modelV2')
# ... 메시지 빌드 ...
msg.valid = True  # SubMaster가 메시지를 인식하는 데 필요
pm.send('modelV2', msg)
```

## 디버깅

### 메시지 수신 확인

```python
#!/usr/bin/env python3
import cereal.messaging as messaging

sm = messaging.SubMaster(["modelV2", "lateralPlan"])
while True:
    sm.update()
    if sm.updated["modelV2"]:
        md = sm["modelV2"]
        print(f"modelV2: frame={md.frameId}, valid={sm.valid['modelV2']}")
        print(f"  position.x[0:5]: {list(md.position.x)[:5]}")
        print(f"  velocity.x[0]: {md.velocity.x[0]:.2f} m/s")
    if sm.updated["lateralPlan"]:
        lp = sm["lateralPlan"]
        print(f"lateralPlan: curvatures={lp.curvatures[:3]}")
```

## 향후 개선 사항

1. 실차 테스트를 위한 안전 장치 추가
2. UI에서 External Model 토글 지원
3. TCP/UDP 등 다양한 통신 프로토콜 지원
4. 외부 모델 연결 상태 모니터링 UI
