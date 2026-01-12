#!/bin/bash
#==============================================================================
# openpilot v0.9.4 Docker Development Environment
# Uses Ubuntu 20.04 container for full compatibility
#==============================================================================

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
IMAGE_NAME="openpilot-dev:v0.9.4"
CONTAINER_NAME="openpilot-dev"

function show_help() {
    echo "openpilot Docker Development Environment"
    echo ""
    echo "Usage: ./docker-dev.sh [command]"
    echo ""
    echo "Commands:"
    echo "  build     Build the Docker image"
    echo "  shell     Start interactive shell in container"
    echo "  run       Run a command in container"
    echo "  scons     Build openpilot with scons"
    echo "  clean     Remove container and image"
    echo ""
    echo "Examples:"
    echo "  ./docker-dev.sh build"
    echo "  ./docker-dev.sh shell"
    echo "  ./docker-dev.sh scons -j8"
    echo ""
}

function build_image() {
    echo "Building Docker image..."
    docker build -f Dockerfile.dev -t "$IMAGE_NAME" .
    echo "Done! Image: $IMAGE_NAME"
}

function run_shell() {
    docker run -it --rm \
        -v "$SCRIPT_DIR:/openpilot" \
        -w /openpilot \
        --name "$CONTAINER_NAME" \
        "$IMAGE_NAME" \
        /bin/bash
}

function run_command() {
    docker run -it --rm \
        -v "$SCRIPT_DIR:/openpilot" \
        -w /openpilot \
        --name "$CONTAINER_NAME" \
        "$IMAGE_NAME" \
        "$@"
}

function run_scons() {
    docker run -it --rm \
        -v "$SCRIPT_DIR:/openpilot" \
        -w /openpilot \
        --name "$CONTAINER_NAME" \
        "$IMAGE_NAME" \
        scons -u "$@"
}

function clean() {
    echo "Removing container and image..."
    docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
    docker rmi "$IMAGE_NAME" 2>/dev/null || true
    echo "Done!"
}

# Main
case "${1:-}" in
    build)
        build_image
        ;;
    shell)
        run_shell
        ;;
    run)
        shift
        run_command "$@"
        ;;
    scons)
        shift
        run_scons "$@"
        ;;
    clean)
        clean
        ;;
    *)
        show_help
        ;;
esac
