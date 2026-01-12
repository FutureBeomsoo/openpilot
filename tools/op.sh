#!/usr/bin/env bash

if [[ ! "${BASH_SOURCE[0]}" = "${0}" ]]; then
  echo "Invalid invocation! This script must not be sourced."
  echo "Run 'op.sh' directly or check your .bashrc for a valid alias"
  return 0
fi

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
UNDERLINE='\033[4m'
BOLD='\033[1m'
NC='\033[0m'

SHELL_NAME="$(basename ${SHELL})"
RC_FILE="${HOME}/.$(basename ${SHELL})rc"
if [ "$(uname)" == "Darwin" ] && [ $SHELL == "/bin/bash" ]; then
  RC_FILE="$HOME/.bash_profile"
fi

function op_install() {
  echo "Installing op system-wide..."
  CMD="\nalias op='"$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )/op.sh" \"\$@\"'\n"
  grep "alias op=" "$RC_FILE" &> /dev/null || printf "$CMD" >> $RC_FILE
  echo -e " ↳ [${GREEN}✔${NC}] op installed successfully. Open a new shell to use it."
}

function loge() {
  if [[ -f "$LOG_FILE" ]]; then
    echo "$1" >> $LOG_FILE
    echo "$2" >> $LOG_FILE
  fi
}

function op_run_command() {
  CMD="$@"

  echo -e "${BOLD}Running command →${NC} $CMD │"
  for ((i=0; i<$((19 + ${#CMD})); i++)); do
    echo -n "─"
  done
  echo -e "┘\n"

  if [[ -z "$DRY" ]]; then
    eval "$CMD"
  fi
}

# by default, assume openpilot dir is in current directory
OPENPILOT_ROOT=$(pwd)
function op_get_openpilot_dir() {
  while [[ "$OPENPILOT_ROOT" != '/' ]];
  do
    if find "$OPENPILOT_ROOT/launch_openpilot.sh" -maxdepth 1 -mindepth 1 &> /dev/null; then
      return 0
    fi
    OPENPILOT_ROOT="$(readlink -f "$OPENPILOT_ROOT/"..)"
  done

  for dir in "$HOME/openpilot" "/data/openpilot"; do
    if [[ -f "$dir/launch_openpilot.sh" ]]; then
      OPENPILOT_ROOT="$dir"
      return 0
    fi
  done
}

function op_check_openpilot_dir() {
  echo "Checking for openpilot directory..."
  if [[ -f "$OPENPILOT_ROOT/launch_openpilot.sh" ]]; then
    echo -e " ↳ [${GREEN}✔${NC}] openpilot found at $OPENPILOT_ROOT"
    return 0
  fi

  echo -e " ↳ [${RED}✗${NC}] openpilot directory not found!"
  return 1
}

function op_check_git() {
  echo "Checking for git..."
  if ! command -v "git" > /dev/null 2>&1; then
    echo -e " ↳ [${RED}✗${NC}] git not found on your system!"
    return 1
  else
    echo -e " ↳ [${GREEN}✔${NC}] git found."
  fi

  echo "Checking for git lfs files..."
  if [[ -f $OPENPILOT_ROOT/selfdrive/modeld/models/supercombo.onnx ]]; then
    if [[ $(file -b $OPENPILOT_ROOT/selfdrive/modeld/models/supercombo.onnx) == "data" ]]; then
      echo -e " ↳ [${GREEN}✔${NC}] git lfs files found."
    else
      echo -e " ↳ [${RED}✗${NC}] git lfs files not found! Run 'git lfs pull'"
      return 1
    fi
  else
    echo -e " ↳ [${GREEN}✔${NC}] git lfs check skipped (model file not present)."
  fi

  echo "Checking for git submodules..."
  if [[ -f "$OPENPILOT_ROOT/.gitmodules" ]]; then
    for name in $(git config --file .gitmodules --get-regexp path | awk '{ print $2 }' | tr '\n' ' '); do
      if [[ -z $(ls $OPENPILOT_ROOT/$name 2>/dev/null) ]]; then
        echo -e " ↳ [${RED}✗${NC}] git submodule $name not found! Run 'git submodule update --init --recursive'"
        return 1
      fi
    done
    echo -e " ↳ [${GREEN}✔${NC}] git submodules found."
  else
    echo -e " ↳ [${GREEN}✔${NC}] No submodules configured."
  fi
}

function op_check_os() {
  echo "Checking for compatible os version..."
  if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    if [ -f "/etc/os-release" ]; then
      source /etc/os-release
      case "$VERSION_CODENAME" in
        "jammy" | "kinetic" | "noble" | "focal")
          echo -e " ↳ [${GREEN}✔${NC}] Ubuntu $VERSION_CODENAME detected."
          ;;
        * )
          echo -e " ↳ [${RED}✗${NC}] Incompatible Ubuntu version $VERSION_CODENAME detected!"
          return 1
          ;;
      esac
    else
      echo -e " ↳ [${RED}✗${NC}] No /etc/os-release on your system!"
      return 1
    fi
  elif [[ "$OSTYPE" == "darwin"* ]]; then
    echo -e " ↳ [${GREEN}✔${NC}] macOS detected."
  else
    echo -e " ↳ [${RED}✗${NC}] OS type $OSTYPE not supported!"
    return 1
  fi
}

function op_check_python() {
  echo "Checking for compatible python version..."
  INSTALLED_PYTHON_VERSION=$(python3 --version 2> /dev/null || true)

  if [[ -z $INSTALLED_PYTHON_VERSION ]]; then
    echo -e " ↳ [${RED}✗${NC}] python3 not found on your system!"
    return 1
  else
    echo -e " ↳ [${GREEN}✔${NC}] $INSTALLED_PYTHON_VERSION detected."
  fi
}

function op_check_pyenv() {
  echo "Checking for pyenv..."
  if command -v pyenv &> /dev/null; then
    echo -e " ↳ [${GREEN}✔${NC}] pyenv detected."
    PYENV_PYTHON_VERSION=$(cat "$OPENPILOT_ROOT/.python-version" 2>/dev/null || echo "")
    if [[ -n "$PYENV_PYTHON_VERSION" ]] && pyenv prefix ${PYENV_PYTHON_VERSION} &> /dev/null; then
      echo -e " ↳ [${GREEN}✔${NC}] Python ${PYENV_PYTHON_VERSION} installed."
    else
      echo -e " ↳ [${RED}✗${NC}] Python ${PYENV_PYTHON_VERSION} not installed. Run 'op setup' first."
      return 1
    fi
  else
    echo -e " ↳ [${RED}✗${NC}] pyenv not found. Run 'op setup' first."
    return 1
  fi
}

function op_activate_pyenv() {
  set +e
  if [[ -f "$HOME/.pyenvrc" ]]; then
    source "$HOME/.pyenvrc"
  fi
  export PATH=$HOME/.pyenv/bin:$HOME/.pyenv/shims:$PATH
  export PYENV_ROOT="$HOME/.pyenv"
  eval "$(pyenv init -)" 2>/dev/null || true
  eval "$(pyenv virtualenv-init -)" 2>/dev/null || true
  set -e
}

function op_before_cmd() {
  if [[ ! -z "$NO_VERIFY" ]]; then
    return 0
  fi

  op_get_openpilot_dir
  cd $OPENPILOT_ROOT

  result="$((op_check_openpilot_dir ) 2>&1)" || (echo -e "$result" && return 1)
  result="${result}\n$(( op_check_git ) 2>&1)" || (echo -e "$result" && return 1)
  result="${result}\n$(( op_check_os ) 2>&1)" || (echo -e "$result" && return 1)
  result="${result}\n$(( op_check_pyenv ) 2>&1)" || (echo -e "$result" && return 1)

  op_activate_pyenv

  result="${result}\n$(( op_check_python ) 2>&1)" || (echo -e "$result" && return 1)

  if [[ -z $VERBOSE ]]; then
    echo -e "${BOLD}Checking system →${NC} [${GREEN}✔${NC}]"
  else
    echo -e "$result"
  fi
}

function op_setup() {
  op_get_openpilot_dir
  cd $OPENPILOT_ROOT

  op_check_openpilot_dir
  op_check_os

  echo "Installing dependencies..."
  st="$(date +%s)"
  if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    SETUP_SCRIPT="tools/ubuntu_setup.sh"
  elif [[ "$OSTYPE" == "darwin"* ]]; then
    SETUP_SCRIPT="tools/mac_setup.sh"
  fi
  if ! $OPENPILOT_ROOT/$SETUP_SCRIPT; then
    echo -e " ↳ [${RED}✗${NC}] Dependencies installation failed!"
    return 1
  fi
  et="$(date +%s)"
  echo -e " ↳ [${GREEN}✔${NC}] Dependencies installed successfully in $((et - st)) seconds."

  echo "Getting git submodules..."
  st="$(date +%s)"
  if ! git submodule update --jobs 4 --init --recursive; then
    echo -e " ↳ [${RED}✗${NC}] Getting git submodules failed!"
    return 1
  fi
  et="$(date +%s)"
  echo -e " ↳ [${GREEN}✔${NC}] Submodules installed successfully in $((et - st)) seconds."

  echo "Pulling git lfs files..."
  st="$(date +%s)"
  if ! git lfs pull; then
    echo -e " ↳ [${RED}✗${NC}] Pulling git lfs files failed!"
    return 1
  fi
  et="$(date +%s)"
  echo -e " ↳ [${GREEN}✔${NC}] Files pulled successfully in $((et - st)) seconds."

  op_check
}

function op_venv() {
  op_get_openpilot_dir
  cd $OPENPILOT_ROOT

  # For pyenv, just start a new shell with pyenv activated
  echo "Starting shell with pyenv environment..."
  case $SHELL_NAME in
    "zsh")
      ZSHRC_DIR=$(mktemp -d 2>/dev/null || mktemp -d -t 'tmp_zsh')
      echo "source $RC_FILE; source ~/.pyenvrc 2>/dev/null || true; cd $OPENPILOT_ROOT" >> $ZSHRC_DIR/.zshrc
      ZDOTDIR=$ZSHRC_DIR zsh ;;
    *)
      bash --rcfile <(echo "source $RC_FILE; source ~/.pyenvrc 2>/dev/null || true; cd $OPENPILOT_ROOT") ;;
  esac
}

function op_check() {
  VERBOSE=1
  op_before_cmd
  unset VERBOSE
}

function op_build() {
  CDIR=$(pwd)
  op_before_cmd
  cd "$CDIR"
  op_run_command scons $@
}

function op_juggle() {
  op_before_cmd
  op_run_command tools/plotjuggler/juggle.py $@
}

function op_lint() {
  op_before_cmd
  op_run_command pre-commit run --all-files $@
}

function op_test() {
  op_before_cmd
  op_run_command pytest $@
}

function op_replay() {
  op_before_cmd
  op_run_command tools/replay/replay $@
}

function op_cabana() {
  op_before_cmd
  op_run_command tools/cabana/cabana $@
}

function op_sim() {
  op_before_cmd
  op_run_command exec tools/sim/run_bridge.py &
  op_run_command exec tools/sim/launch_openpilot.sh
}

function op_default() {
  echo "An openpilot helper (v0.9.4)"
  echo ""
  echo -e "${BOLD}${UNDERLINE}Description:${NC}"
  echo "  op is your entry point for all things related to openpilot development."
  echo "  Uses pyenv + poetry for Python environment management."
  echo ""
  echo -e "${BOLD}${UNDERLINE}Usage:${NC} op [OPTIONS] <COMMAND>"
  echo ""
  echo -e "${BOLD}${UNDERLINE}Commands [System]:${NC}"
  echo -e "  ${BOLD}check${NC}        Check the development environment"
  echo -e "  ${BOLD}venv${NC}         Open a shell with pyenv environment"
  echo -e "  ${BOLD}setup${NC}        Install openpilot dependencies"
  echo -e "  ${BOLD}build${NC}        Build openpilot with scons"
  echo -e "  ${BOLD}install${NC}      Install the 'op' tool system wide"
  echo ""
  echo -e "${BOLD}${UNDERLINE}Commands [Tooling]:${NC}"
  echo -e "  ${BOLD}juggle${NC}       Run PlotJuggler"
  echo -e "  ${BOLD}replay${NC}       Run Replay"
  echo -e "  ${BOLD}cabana${NC}       Run Cabana"
  echo ""
  echo -e "${BOLD}${UNDERLINE}Commands [Testing]:${NC}"
  echo -e "  ${BOLD}sim${NC}          Run openpilot in a simulator"
  echo -e "  ${BOLD}lint${NC}         Run the linter"
  echo -e "  ${BOLD}test${NC}         Run all unit tests from pytest"
  echo ""
  echo -e "${BOLD}${UNDERLINE}Options:${NC}"
  echo -e "  ${BOLD}-d, --dir${NC}           Specify the openpilot directory"
  echo -e "  ${BOLD}--dry${NC}               Don't run anything, just print"
  echo -e "  ${BOLD}-n, --no-verify${NC}     Skip environment check"
  echo ""
  echo -e "${BOLD}${UNDERLINE}Examples:${NC}"
  echo "  op setup              # Install dependencies"
  echo "  op build -j8          # Build with 8 cores"
  echo "  op venv               # Open pyenv shell"
}

function _op() {
  # parse Options
  case $1 in
    -d | --dir )       shift 1; OPENPILOT_ROOT="$1"; shift 1 ;;
    --dry )            shift 1; DRY="1" ;;
    -n | --no-verify ) shift 1; NO_VERIFY="1" ;;
    -l | --log )       shift 1; LOG_FILE="$1" ; shift 1 ;;
  esac

  # parse Commands
  case $1 in
    venv )          shift 1; op_venv "$@" ;;
    check )         shift 1; op_check "$@" ;;
    setup )         shift 1; op_setup "$@" ;;
    build )         shift 1; op_build "$@" ;;
    juggle )        shift 1; op_juggle "$@" ;;
    cabana )        shift 1; op_cabana "$@" ;;
    lint )          shift 1; op_lint "$@" ;;
    test )          shift 1; op_test "$@" ;;
    replay )        shift 1; op_replay "$@" ;;
    sim )           shift 1; op_sim "$@" ;;
    install )       shift 1; op_install "$@" ;;
    * ) op_default "$@" ;;
  esac
}

_op $@
