#!/bin/bash
# Activate pyenv and poetry environment for openpilot development

export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PYENV_ROOT/shims:$PATH"
eval "$(pyenv init -)"

# Set display for GUI apps
export DISPLAY=${DISPLAY:-:0}
export QT_X11_NO_MITSHM=1
export XDG_RUNTIME_DIR=/tmp/runtime-root
mkdir -p $XDG_RUNTIME_DIR

# Git safe directory
git config --global --add safe.directory /home/pbs/openpilot_ws/openpilot_e2e 2>/dev/null

echo "Environment activated. Run 'poetry shell' to enter virtual environment."
echo "Or use 'poetry run <command>' to run commands directly."

# Enter poetry shell
poetry shell
