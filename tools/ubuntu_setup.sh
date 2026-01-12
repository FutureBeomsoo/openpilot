#!/usr/bin/env bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

# NOTE: this is used in a docker build, so do not run any scripts here.

echo "=================================="
echo "  openpilot v0.9.4 Setup Script"
echo "  Ubuntu 20.04 / 22.04 / 24.04"
echo "=================================="
echo ""

# Install system dependencies
"$DIR"/install_ubuntu_dependencies.sh

# Install Python dependencies
"$DIR"/install_python_dependencies.sh

echo ""
echo "=================================="
echo "  OPENPILOT SETUP COMPLETE"
echo "=================================="
echo ""
echo "To activate the environment:"
echo "  source .venv/bin/activate"
echo ""
echo "To build openpilot:"
echo "  scons -u -j\$(nproc)"
echo ""
