#!/bin/bash
# openpilot v0.9.4 개발용 Docker 실행 스크립트
# 로컬 코드를 마운트하고 빌드 후 bash 진입

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENPILOT_DIR="$(cd "$DIR/../.." && pwd)"

# X11 디스플레이 권한
xhost +local:docker 2>/dev/null || true

docker run -it --rm \
  --gpus all \
  --name openpilot-dev \
  -e DISPLAY=$DISPLAY \
  -v /tmp/.X11-unix:/tmp/.X11-unix \
  -v "$OPENPILOT_DIR":/root/openpilot \
  --network host \
  --privileged \
  openpilot-sim:v094 \
  bash -c "cd /root/openpilot && scons -j\$(nproc) && exec /bin/bash"
