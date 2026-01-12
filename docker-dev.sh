#!/bin/bash
# Development Docker helper script for openpilot
# Based on tools/sim/start_openpilot_docker.sh

set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
cd "$DIR"

IMAGE_NAME="openpilot-dev:focal"
CONTAINER_NAME="openpilot-dev"

# Host path to mount
HOST_OPENPILOT_PATH="${HOST_OPENPILOT_PATH:-$(pwd)}"
# Container path
CONTAINER_OPENPILOT_PATH="/home/pbs/openpilot_ws/openpilot_e2e"

usage() {
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  build       Build the Docker image (uses ghcr.io/commaai/openpilot-base)"
    echo "  run         Run the Docker container (interactive)"
    echo "  exec        Execute bash in running container"
    echo "  stop        Stop the running container"
    echo "  help        Show this help message"
    echo ""
    echo "Environment variables:"
    echo "  HOST_OPENPILOT_PATH  Path to openpilot on host (default: current directory)"
    echo ""
    echo "After 'run', inside container:"
    echo "  poetry shell"
    echo "  scons -u -j\$(nproc)"
}

build_image() {
    echo "Building Docker image: ${IMAGE_NAME}"
    echo "Base image: ghcr.io/commaai/openpilot-base:latest"
    docker build \
        -t ${IMAGE_NAME} \
        -f Dockerfile.dev \
        .
    echo ""
    echo "Docker image built successfully: ${IMAGE_NAME}"
}

run_container() {
    # Stop existing container if running
    docker rm -f ${CONTAINER_NAME} 2>/dev/null || true

    echo "Starting Docker container: ${CONTAINER_NAME}"
    echo "Mounting: ${HOST_OPENPILOT_PATH} -> ${CONTAINER_OPENPILOT_PATH}"

    # Allow X11 forwarding (for GUI apps like ui)
    xhost +local:root 2>/dev/null || true

    docker run -it \
        --name ${CONTAINER_NAME} \
        --net=host \
        --privileged \
        -e DISPLAY=${DISPLAY} \
        -e QT_X11_NO_MITSHM=1 \
        -v /tmp/.X11-unix:/tmp/.X11-unix \
        -v "${HOST_OPENPILOT_PATH}:${CONTAINER_OPENPILOT_PATH}" \
        --shm-size 2G \
        -w ${CONTAINER_OPENPILOT_PATH} \
        ${IMAGE_NAME} \
        /bin/bash
}

exec_container() {
    echo "Executing bash in container: ${CONTAINER_NAME}"
    docker exec -it ${CONTAINER_NAME} /bin/bash
}

stop_container() {
    echo "Stopping container: ${CONTAINER_NAME}"
    docker stop ${CONTAINER_NAME} 2>/dev/null || true
    docker rm ${CONTAINER_NAME} 2>/dev/null || true
    echo "Container stopped"
}

case "${1:-help}" in
    build)
        build_image
        ;;
    run)
        run_container
        ;;
    exec)
        exec_container
        ;;
    stop)
        stop_container
        ;;
    help|*)
        usage
        ;;
esac
