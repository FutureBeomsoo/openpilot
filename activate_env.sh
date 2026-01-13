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

# Git safe directory (main repo + submodules)
git config --global --add safe.directory /home/pbs/openpilot_ws/openpilot_e2e 2>/dev/null
git config --global --add safe.directory /home/pbs/openpilot_ws/openpilot_e2e/cereal 2>/dev/null
git config --global --add safe.directory /home/pbs/openpilot_ws/openpilot_e2e/opendbc 2>/dev/null
git config --global --add safe.directory /home/pbs/openpilot_ws/openpilot_e2e/panda 2>/dev/null
git config --global --add safe.directory /home/pbs/openpilot_ws/openpilot_e2e/body 2>/dev/null
git config --global --add safe.directory /home/pbs/openpilot_ws/openpilot_e2e/laika_repo 2>/dev/null
git config --global --add safe.directory /home/pbs/openpilot_ws/openpilot_e2e/rednose_repo 2>/dev/null
git config --global --add safe.directory /home/pbs/openpilot_ws/openpilot_e2e/tinygrad_repo 2>/dev/null
git config --global --add safe.directory /home/pbs/openpilot_ws/openpilot_e2e/msgq_repo 2>/dev/null

# Activate poetry virtual environment directly (no subshell)
source /home/pbs/openpilot_ws/openpilot_e2e/.venv/bin/activate

echo "Environment activated! (pyenv + poetry venv)"
