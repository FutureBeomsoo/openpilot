#!/bin/bash
# openpilot v0.9.4 Docker 시뮬레이터 실행 스크립트
# CARLA 시뮬레이터와 연동하여 openpilot 테스트
#
# 사용법:
#   Terminal 1: ./start_carla.sh
#   Terminal 2: ./start_openpilot_docker_v094.sh

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
cd $DIR

# 사용할 이미지 설정
DOCKER_IMAGE="openpilot:v094"
CONTAINER_NAME="openpilot_client_v094"

# openpilot 경로 설정
OPENPILOT_DIR="/root/openpilot"

# 로컬 소스 마운트 옵션 (개발용)
EXTRA_ARGS=""
if [[ ! -z "$MOUNT_OPENPILOT" ]]; then
  LOCAL_OPENPILOT_DIR="$(dirname $(dirname $DIR))"
  OPENPILOT_DIR="$LOCAL_OPENPILOT_DIR"
  EXTRA_ARGS="-v $LOCAL_OPENPILOT_DIR:$LOCAL_OPENPILOT_DIR -e PYTHONPATH=$LOCAL_OPENPILOT_DIR"
  echo "로컬 소스 마운트: $LOCAL_OPENPILOT_DIR"
fi

# CI 환경이 아닌 경우 X11 설정
if [[ -z "$CI" ]]; then
  # X11 연결 허용
  xhost +local:root 2>/dev/null || echo "Warning: xhost 명령 실패 (X11 포워딩 불가할 수 있음)"

  CMD="./tmux_script.sh $*"
  EXTRA_ARGS="${EXTRA_ARGS} -it"
else
  CMD="CI=1 ${OPENPILOT_DIR}/tools/sim/tests/test_carla_integration.py"
fi

# 기존 컨테이너 종료
docker kill $CONTAINER_NAME 2>/dev/null || true

echo "================================================"
echo "openpilot v0.9.4 시뮬레이터 시작"
echo "이미지: $DOCKER_IMAGE"
echo "작업 디렉토리: $OPENPILOT_DIR/tools/sim"
echo "================================================"

# 컨테이너 실행
docker run --net=host \
  --name $CONTAINER_NAME \
  --rm \
  --gpus all \
  --device=/dev/dri:/dev/dri \
  --device=/dev/input:/dev/input \
  -v /tmp/.X11-unix:/tmp/.X11-unix \
  --shm-size 1G \
  -e DISPLAY=$DISPLAY \
  -e QT_X11_NO_MITSHM=1 \
  -w "$OPENPILOT_DIR/tools/sim" \
  $EXTRA_ARGS \
  $DOCKER_IMAGE \
  /bin/bash -c "$CMD"
