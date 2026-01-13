#!/bin/bash
# Activate pyenv and poetry environment for openpilot development
# Usage: source activate_env.sh

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

echo "Environment activated! (pyenv + poetry venv)"
