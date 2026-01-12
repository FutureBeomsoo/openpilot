#!/usr/bin/env bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
ROOT="$DIR/../"
cd "$ROOT"

RC_FILE="${HOME}/.$(basename ${SHELL})rc"
if [ "$(uname)" == "Darwin" ] && [ $SHELL == "/bin/bash" ]; then
  RC_FILE="$HOME/.bash_profile"
fi

# Install pyenv if not present
if ! command -v "pyenv" > /dev/null 2>&1; then
  echo "Installing pyenv..."
  curl -L https://github.com/pyenv/pyenv-installer/raw/master/bin/pyenv-installer | bash

  # Add pyenv to RC file
  if ! grep -q "pyenvrc" "$RC_FILE" 2>/dev/null; then
    echo -e "\n. ~/.pyenvrc" >> $RC_FILE
  fi

  cat <<EOF > "${HOME}/.pyenvrc"
if [ -z "\$PYENV_ROOT" ]; then
  export PATH=\$HOME/.pyenv/bin:\$HOME/.pyenv/shims:\$PATH
  export PYENV_ROOT="\$HOME/.pyenv"
  eval "\$(pyenv init -)"
  eval "\$(pyenv virtualenv-init -)"
fi
EOF

  # Setup now without restarting shell
  export PATH=$HOME/.pyenv/bin:$HOME/.pyenv/shims:$PATH
  export PYENV_ROOT="$HOME/.pyenv"
  eval "$(pyenv init -)"
  eval "$(pyenv virtualenv-init -)"
fi

# Ensure pyenv is in PATH for current session
export PATH=$HOME/.pyenv/bin:$HOME/.pyenv/shims:$PATH
export PYENV_ROOT="$HOME/.pyenv"
eval "$(pyenv init -)" 2>/dev/null || true
eval "$(pyenv virtualenv-init -)" 2>/dev/null || true

export MAKEFLAGS="-j$(nproc)"

# Get required Python version
PYENV_PYTHON_VERSION=$(cat "$ROOT/.python-version")
echo "Required Python version: $PYENV_PYTHON_VERSION"

# Install Python if not present
if ! pyenv prefix ${PYENV_PYTHON_VERSION} &> /dev/null; then
  if [ "$(uname)" == "Linux" ]; then
    echo "Updating pyenv..."
    pyenv update || true
  fi
  echo "Installing Python ${PYENV_PYTHON_VERSION}..."
  CONFIGURE_OPTS="--enable-shared" pyenv install -f ${PYENV_PYTHON_VERSION}
fi

eval "$(pyenv init --path)"

echo "Updating pip..."
pip install --upgrade pip==22.3.1

echo "Installing poetry..."
pip install poetry==1.2.2

# Configure poetry
poetry config virtualenvs.prefer-active-python true --local

# Set PYTHONPATH
echo "PYTHONPATH=${ROOT}" > "$ROOT/.env"
poetry self add poetry-dotenv-plugin@^0.1.0 || true

echo "Installing Python packages with poetry..."
POETRY_INSTALL_ARGS="--no-cache --no-root"
poetry install $POETRY_INSTALL_ARGS

pyenv rehash

# Install pre-commit hooks
if [ "$(uname)" != "Darwin" ]; then
  echo "Installing pre-commit hooks..."
  if [ -f "$ROOT/.pre-commit-config.yaml" ]; then
    cd "$ROOT"
    poetry run pre-commit install || true
  fi
fi

echo ""
echo "Python dependencies installed successfully."
echo "The environment will be automatically activated via pyenv."
