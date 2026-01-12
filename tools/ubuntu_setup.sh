#!/usr/bin/env bash
set -e

#==============================================================================
# openpilot v0.9.4 Setup Script
# Supports: Ubuntu 20.04 / 22.04 / 24.04
#==============================================================================

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
ROOT="$(cd $DIR/../ && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
BOLD='\033[1m'
NC='\033[0m'

echo "=================================="
echo "  openpilot v0.9.4 Setup Script"
echo "  Ubuntu 20.04 / 22.04 / 24.04"
echo "=================================="
echo ""

#------------------------------------------------------------------------------
# Step 1: System Dependencies
#------------------------------------------------------------------------------
echo -e "${BOLD}[1/5] Installing system dependencies...${NC}"

SUDO=""
if [[ ! $(id -u) -eq 0 ]]; then
  if [[ -z $(which sudo) ]]; then
    echo "Please install sudo or run as root"
    exit 1
  fi
  SUDO="sudo"
fi

$SUDO apt-get update

# Detect Ubuntu version
source /etc/os-release
echo "Detected: $ID $VERSION_ID ($VERSION_CODENAME)"

# Common packages for all Ubuntu versions
$SUDO apt-get install -y --no-install-recommends \
  autoconf \
  build-essential \
  ca-certificates \
  clang \
  cmake \
  make \
  cppcheck \
  libtool \
  curl \
  locales \
  git \
  git-lfs \
  bzip2 \
  liblzma-dev \
  libarchive-dev \
  libbz2-dev \
  capnproto \
  libcapnp-dev \
  libcurl4-openssl-dev \
  ffmpeg \
  libavformat-dev \
  libavcodec-dev \
  libavdevice-dev \
  libavutil-dev \
  libavfilter-dev \
  libeigen3-dev \
  libffi-dev \
  libglew-dev \
  libgles2-mesa-dev \
  libglfw3-dev \
  libglib2.0-0 \
  libomp-dev \
  libopencv-dev \
  libportaudio2 \
  libssl-dev \
  libsqlite3-dev \
  libusb-1.0-0-dev \
  libzmq3-dev \
  libsystemd-dev \
  opencl-headers \
  ocl-icd-libopencl1 \
  ocl-icd-opencl-dev \
  clinfo \
  portaudio19-dev \
  qml-module-qtquick2 \
  qtmultimedia5-dev \
  qtlocation5-dev \
  qtpositioning5-dev \
  qttools5-dev-tools \
  libqt5sql5-sqlite \
  libqt5svg5-dev \
  libqt5charts5-dev \
  libqt5x11extras5-dev \
  libreadline-dev \
  valgrind

# Version-specific packages
case "$VERSION_CODENAME" in
  "noble")  # Ubuntu 24.04
    $SUDO apt-get install -y --no-install-recommends \
      libswresample-dev \
      libncurses-dev \
      libpng-dev \
      libdw1 \
      g++-12 \
      qtbase5-dev \
      qtchooser \
      qt5-qmake \
      qtbase5-dev-tools \
      python3-dev \
      python3-venv
    ;;
  "jammy" | "kinetic")  # Ubuntu 22.04
    $SUDO apt-get install -y --no-install-recommends \
      libncurses5-dev \
      libncursesw5-dev \
      libpng16-16 \
      libdw1 \
      g++-12 \
      qtbase5-dev \
      qtchooser \
      qt5-qmake \
      qtbase5-dev-tools \
      python3-dev
    ;;
  "focal")  # Ubuntu 20.04
    $SUDO apt-get install -y --no-install-recommends \
      libncurses5-dev \
      libncursesw5-dev \
      libpng16-16 \
      libdw1 \
      libavresample-dev \
      qt5-default \
      python-dev
    ;;
  *)
    echo "Warning: Unsupported Ubuntu version, trying noble packages..."
    $SUDO apt-get install -y --no-install-recommends \
      libswresample-dev \
      libncurses-dev \
      libpng-dev \
      g++-12 \
      qtbase5-dev \
      python3-dev \
      python3-venv || true
    ;;
esac

# Setup udev rules
if [[ -d "/etc/udev/rules.d/" ]]; then
  $SUDO tee /etc/udev/rules.d/11-panda.rules > /dev/null <<EOF
SUBSYSTEM=="usb", ATTRS{idVendor}=="0483", ATTRS{idProduct}=="df11", MODE="0666"
SUBSYSTEM=="usb", ATTRS{idVendor}=="3801", ATTRS{idProduct}=="ddcc", MODE="0666"
SUBSYSTEM=="usb", ATTRS{idVendor}=="3801", ATTRS{idProduct}=="ddee", MODE="0666"
SUBSYSTEM=="usb", ATTRS{idVendor}=="bbaa", ATTRS{idProduct}=="ddcc", MODE="0666"
SUBSYSTEM=="usb", ATTRS{idVendor}=="bbaa", ATTRS{idProduct}=="ddee", MODE="0666"
EOF
  $SUDO udevadm control --reload-rules && $SUDO udevadm trigger || true
fi

echo -e " ↳ [${GREEN}✔${NC}] System dependencies installed."

#------------------------------------------------------------------------------
# Step 2: Git LFS
#------------------------------------------------------------------------------
echo -e "${BOLD}[2/5] Setting up Git LFS...${NC}"

cd "$ROOT"
git lfs install
git lfs pull

# Verify LFS files
if [[ -f "$ROOT/poetry.lock" ]]; then
  if head -1 "$ROOT/poetry.lock" | grep -q "version https://git-lfs"; then
    echo -e " ↳ [${RED}✗${NC}] Git LFS files not properly pulled!"
    exit 1
  fi
fi

echo -e " ↳ [${GREEN}✔${NC}] Git LFS configured."

#------------------------------------------------------------------------------
# Step 3: Git Submodules
#------------------------------------------------------------------------------
echo -e "${BOLD}[3/5] Updating git submodules...${NC}"

cd "$ROOT"
git submodule update --init --recursive

echo -e " ↳ [${GREEN}✔${NC}] Submodules updated."

#------------------------------------------------------------------------------
# Step 4: Python (pyenv + poetry)
#------------------------------------------------------------------------------
echo -e "${BOLD}[4/5] Setting up Python environment...${NC}"

RC_FILE="${HOME}/.bashrc"
[[ -f "${HOME}/.zshrc" ]] && RC_FILE="${HOME}/.zshrc"

# Install pyenv if not present
if [[ ! -d "$HOME/.pyenv" ]]; then
  echo "Installing pyenv..."
  curl -L https://github.com/pyenv/pyenv-installer/raw/master/bin/pyenv-installer | bash
fi

# Create pyenvrc
cat <<'PYENVRC' > "${HOME}/.pyenvrc"
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PYENV_ROOT/shims:$PATH"
eval "$(pyenv init -)"
eval "$(pyenv virtualenv-init -)"
PYENVRC

# Add to RC file
if ! grep -q "pyenvrc" "$RC_FILE" 2>/dev/null; then
  echo -e "\n# pyenv\nsource ~/.pyenvrc" >> "$RC_FILE"
fi

# Activate pyenv for this session
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PYENV_ROOT/shims:$PATH"
eval "$(pyenv init -)"
eval "$(pyenv virtualenv-init -)"

# Install required Python version
PYTHON_VERSION=$(cat "$ROOT/.python-version")
echo "Required Python: $PYTHON_VERSION"

if ! pyenv versions | grep -q "$PYTHON_VERSION"; then
  echo "Installing Python $PYTHON_VERSION (this may take a few minutes)..."
  CONFIGURE_OPTS="--enable-shared" pyenv install -f "$PYTHON_VERSION"
fi

# Set local Python version
cd "$ROOT"
pyenv local "$PYTHON_VERSION"
pyenv rehash

# Verify Python version
CURRENT_PY=$(python --version 2>&1)
echo "Active Python: $CURRENT_PY"

# Install pip and poetry
pip install --upgrade pip==22.3.1
pip install poetry==1.2.2
pyenv rehash

# Configure poetry
poetry config virtualenvs.prefer-active-python true --local
poetry config virtualenvs.in-project false --local
poetry env use "$(pyenv which python)"

# Install Python dependencies
echo "Installing Python packages..."
poetry install --no-cache --no-root

# Setup PYTHONPATH
echo "PYTHONPATH=${ROOT}" > "$ROOT/.env"
poetry self add poetry-dotenv-plugin@^0.1.0 || true

pyenv rehash

echo -e " ↳ [${GREEN}✔${NC}] Python environment configured."

#------------------------------------------------------------------------------
# Step 5: Finalize
#------------------------------------------------------------------------------
echo -e "${BOLD}[5/5] Finalizing...${NC}"

# Add openpilot_env to bashrc
if [[ -f "$ROOT/tools/openpilot_env.sh" ]]; then
  if ! grep -q "openpilot_env.sh" "$RC_FILE" 2>/dev/null; then
    echo -e "\nsource $ROOT/tools/openpilot_env.sh" >> "$RC_FILE"
  fi
fi

echo -e " ↳ [${GREEN}✔${NC}] Configuration complete."

#------------------------------------------------------------------------------
# Done
#------------------------------------------------------------------------------
echo ""
echo "=================================="
echo -e "  ${GREEN}SETUP COMPLETE${NC}"
echo "=================================="
echo ""
echo "To apply environment changes:"
echo "  source ~/.bashrc"
echo ""
echo "To build openpilot:"
echo "  scons -u -j\$(nproc)"
echo ""
