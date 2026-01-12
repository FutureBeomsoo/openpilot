#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
ROOT="$(cd $DIR/../ && pwd)"
SUDO=""

# NOTE: this is used in a docker build, so do not run any scripts here.

# Use sudo if not root
if [[ ! $(id -u) -eq 0 ]]; then
  if [[ -z $(which sudo) ]]; then
    echo "Please install sudo or run as root"
    exit 1
  fi
  SUDO="sudo"
fi

# Install packages present in all supported versions of Ubuntu
function install_ubuntu_common_requirements() {
  $SUDO apt-get update
  $SUDO apt-get install -y --no-install-recommends \
    autoconf \
    build-essential \
    ca-certificates \
    casync \
    clang \
    cmake \
    make \
    cppcheck \
    libtool \
    gcc-arm-none-eabi \
    bzip2 \
    liblzma-dev \
    libarchive-dev \
    libbz2-dev \
    capnproto \
    libcapnp-dev \
    curl \
    libcurl4-openssl-dev \
    git \
    git-lfs \
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
    libncurses5-dev \
    libncursesw5-dev \
    libomp-dev \
    libopencv-dev \
    libpng16-16 \
    libportaudio2 \
    libssl-dev \
    libsqlite3-dev \
    libusb-1.0-0-dev \
    libzmq3-dev \
    libsystemd-dev \
    locales \
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
    libdw1 \
    valgrind
}

# Install Ubuntu 24.04 LTS packages
function install_ubuntu_noble_requirements() {
  $SUDO apt-get update
  $SUDO apt-get install -y --no-install-recommends \
    autoconf \
    build-essential \
    ca-certificates \
    clang \
    cmake \
    make \
    cppcheck \
    libtool \
    gcc-arm-none-eabi \
    bzip2 \
    liblzma-dev \
    libarchive-dev \
    libbz2-dev \
    capnproto \
    libcapnp-dev \
    curl \
    libcurl4-openssl-dev \
    git \
    git-lfs \
    ffmpeg \
    libavformat-dev \
    libavcodec-dev \
    libavdevice-dev \
    libavutil-dev \
    libavfilter-dev \
    libswresample-dev \
    libeigen3-dev \
    libffi-dev \
    libglew-dev \
    libgles2-mesa-dev \
    libglfw3-dev \
    libglib2.0-0 \
    libncurses-dev \
    libomp-dev \
    libopencv-dev \
    libpng-dev \
    libportaudio2 \
    libssl-dev \
    libsqlite3-dev \
    libusb-1.0-0-dev \
    libzmq3-dev \
    libsystemd-dev \
    locales \
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
    libdw1 \
    valgrind \
    g++-12 \
    qtbase5-dev \
    qtchooser \
    qt5-qmake \
    qtbase5-dev-tools \
    python3-dev \
    python3-venv

  # casync is not available in Ubuntu 24.04, install from source or skip
  if ! command -v casync &> /dev/null; then
    echo "WARNING: casync is not available in Ubuntu 24.04 repositories."
    echo "If needed, install from: https://github.com/systemd/casync"
  fi
}

# Install Ubuntu 22.04 LTS packages
function install_ubuntu_lts_latest_requirements() {
  install_ubuntu_common_requirements

  $SUDO apt-get install -y --no-install-recommends \
    g++-12 \
    qtbase5-dev \
    qtchooser \
    qt5-qmake \
    qtbase5-dev-tools \
    python3-dev
}

# Install Ubuntu 20.04 packages
function install_ubuntu_focal_requirements() {
  install_ubuntu_common_requirements

  $SUDO apt-get install -y --no-install-recommends \
    libavresample-dev \
    qt5-default \
    python-dev
}

# Setup udev rules for panda/device development
function setup_udev_rules() {
  if [[ -d "/etc/udev/rules.d/" ]]; then
    echo "Setting up udev rules..."

    # Setup jungle udev rules
    $SUDO tee /etc/udev/rules.d/12-panda_jungle.rules > /dev/null <<EOF
SUBSYSTEM=="usb", ATTRS{idVendor}=="3801", ATTRS{idProduct}=="ddcf", MODE="0666"
SUBSYSTEM=="usb", ATTRS{idVendor}=="3801", ATTRS{idProduct}=="ddef", MODE="0666"
SUBSYSTEM=="usb", ATTRS{idVendor}=="bbaa", ATTRS{idProduct}=="ddcf", MODE="0666"
SUBSYSTEM=="usb", ATTRS{idVendor}=="bbaa", ATTRS{idProduct}=="ddef", MODE="0666"
EOF

    # Setup panda udev rules
    $SUDO tee /etc/udev/rules.d/11-panda.rules > /dev/null <<EOF
SUBSYSTEM=="usb", ATTRS{idVendor}=="0483", ATTRS{idProduct}=="df11", MODE="0666"
SUBSYSTEM=="usb", ATTRS{idVendor}=="3801", ATTRS{idProduct}=="ddcc", MODE="0666"
SUBSYSTEM=="usb", ATTRS{idVendor}=="3801", ATTRS{idProduct}=="ddee", MODE="0666"
SUBSYSTEM=="usb", ATTRS{idVendor}=="bbaa", ATTRS{idProduct}=="ddcc", MODE="0666"
SUBSYSTEM=="usb", ATTRS{idVendor}=="bbaa", ATTRS{idProduct}=="ddee", MODE="0666"
EOF

    # Setup adb udev rules
    $SUDO tee /etc/udev/rules.d/50-comma-adb.rules > /dev/null <<EOF
SUBSYSTEM=="usb", ATTR{idVendor}=="04d8", ATTR{idProduct}=="1234", ENV{adb_user}="yes"
EOF

    $SUDO udevadm control --reload-rules && $SUDO udevadm trigger || true
    echo "udev rules installed."
  fi
}

# Detect OS using /etc/os-release file
if [ -f "/etc/os-release" ]; then
  source /etc/os-release
  case "$VERSION_CODENAME" in
    "noble")
      echo "Detected Ubuntu 24.04 (Noble)"
      install_ubuntu_noble_requirements
      setup_udev_rules
      ;;
    "jammy")
      echo "Detected Ubuntu 22.04 (Jammy)"
      install_ubuntu_lts_latest_requirements
      setup_udev_rules
      ;;
    "kinetic")
      echo "Detected Ubuntu 22.10 (Kinetic)"
      install_ubuntu_lts_latest_requirements
      setup_udev_rules
      ;;
    "focal")
      echo "Detected Ubuntu 20.04 (Focal)"
      install_ubuntu_focal_requirements
      setup_udev_rules
      ;;
    *)
      echo "$ID $VERSION_ID is unsupported. This setup script is written for Ubuntu 20.04/22.04/24.04."
      read -p "Would you like to attempt installation anyway? " -n 1 -r
      echo ""
      if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
      fi
      # Try noble (24.04) requirements for newer Ubuntu versions
      install_ubuntu_noble_requirements
      setup_udev_rules
  esac
else
  echo "No /etc/os-release in the system"
  exit 1
fi


# install python dependencies
$ROOT/update_requirements.sh

source ~/.bashrc
if [ -z "$OPENPILOT_ENV" ]; then
  printf "\nsource %s/tools/openpilot_env.sh" "$ROOT" >> ~/.bashrc
  source ~/.bashrc
  echo "added openpilot_env to bashrc"
fi

echo
echo "----   OPENPILOT SETUP DONE   ----"
echo "Open a new shell or configure your active shell env by running:"
echo "source ~/.bashrc"
