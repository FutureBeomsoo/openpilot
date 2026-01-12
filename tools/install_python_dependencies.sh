#!/usr/bin/env bash
set -euo pipefail

# Increase the pip timeout to handle TimeoutError
export PIP_DEFAULT_TIMEOUT=200

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
ROOT="$DIR"/../
cd "$ROOT"

# Install uv if not present
if ! command -v "uv" > /dev/null 2>&1; then
  echo "Installing uv..."
  curl -LsSf --retry 5 --retry-delay 5 --retry-all-errors https://astral.sh/uv/install.sh | sh
  UV_BIN="$HOME/.local/bin"
  PATH="$UV_BIN:$PATH"
fi

echo "Updating uv..."
uv self update || true

# Check if pyproject.toml exists
if [[ ! -f "$ROOT/pyproject.toml" ]]; then
  echo "ERROR: pyproject.toml not found in $ROOT"
  exit 1
fi

echo "Creating virtual environment and installing Python packages..."

# Create .venv if it doesn't exist
if [[ ! -d "$ROOT/.venv" ]]; then
  # Get Python version from .python-version if exists
  if [[ -f "$ROOT/.python-version" ]]; then
    PYTHON_VERSION=$(cat "$ROOT/.python-version")
    echo "Using Python version: $PYTHON_VERSION"
    uv venv --python "$PYTHON_VERSION" "$ROOT/.venv" || uv venv "$ROOT/.venv"
  else
    uv venv "$ROOT/.venv"
  fi
fi

# Install dependencies using uv
echo "Installing Python packages with uv..."
uv sync --frozen --all-extras 2>/dev/null || uv pip install -r <(uv pip compile pyproject.toml) --python "$ROOT/.venv/bin/python"

# Activate and verify
source "$ROOT/.venv/bin/activate"

# Create .env file for environment variables
if [[ ! -f "$ROOT/.env" ]]; then
  touch "$ROOT/.env"
  echo "PYTHONPATH=${ROOT}" >> "$ROOT/.env"
fi

# macOS specific settings
if [[ "$(uname)" == 'Darwin' ]]; then
  echo "# msgq doesn't work on mac" >> "$ROOT/.env"
  echo "export ZMQ=1" >> "$ROOT/.env"
  echo "export OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES" >> "$ROOT/.env"
fi

echo ""
echo "Python dependencies installed successfully."
echo "Activate the virtual environment with: source .venv/bin/activate"
