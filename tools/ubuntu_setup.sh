#!/usr/bin/env bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
ROOT="$(cd $DIR/../ && pwd)"

# NOTE: this is used in a docker build, so do not run any scripts here.

echo "=================================="
echo "  openpilot v0.9.4 Setup Script"
echo "  Ubuntu 20.04 / 22.04 / 24.04"
echo "=================================="
echo ""

# Install system dependencies
"$DIR"/install_ubuntu_dependencies.sh

# Install Python dependencies (pyenv + poetry)
"$DIR"/install_python_dependencies.sh

# Add openpilot_env to bashrc if not present
RC_FILE="${HOME}/.$(basename ${SHELL})rc"
if [ "$(uname)" == "Darwin" ] && [ $SHELL == "/bin/bash" ]; then
  RC_FILE="$HOME/.bash_profile"
fi

if [ -z "$OPENPILOT_ENV" ] && [ -f "$ROOT/tools/openpilot_env.sh" ]; then
  if ! grep -q "openpilot_env.sh" "$RC_FILE" 2>/dev/null; then
    printf "\nsource %s/tools/openpilot_env.sh" "$ROOT" >> "$RC_FILE"
    echo "Added openpilot_env to $RC_FILE"
  fi
fi

echo ""
echo "=================================="
echo "  OPENPILOT SETUP COMPLETE"
echo "=================================="
echo ""
echo "To apply environment changes:"
echo "  source ~/.bashrc"
echo ""
echo "To build openpilot:"
echo "  scons -u -j\$(nproc)"
echo ""
