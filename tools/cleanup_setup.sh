#!/bin/bash
#==============================================================================
# openpilot 설정 되돌리기 스크립트
# 이전 설정으로 인한 변경사항을 제거합니다
#==============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

echo "=================================="
echo "  openpilot 설정 정리 스크립트"
echo "=================================="
echo ""

RC_FILE="${HOME}/.bashrc"
[[ -n "$ZSH_VERSION" ]] && RC_FILE="${HOME}/.zshrc"

# 1. pyenvrc 제거
echo -e "${BOLD}[1/5] ~/.pyenvrc 제거...${NC}"
if [[ -f "$HOME/.pyenvrc" ]]; then
    rm -f "$HOME/.pyenvrc"
    echo -e " ↳ [${GREEN}✔${NC}] ~/.pyenvrc 삭제됨"
else
    echo -e " ↳ [${YELLOW}!${NC}] ~/.pyenvrc 없음 (건너뜀)"
fi

# 2. bashrc/zshrc에서 pyenv 관련 줄 제거
echo -e "${BOLD}[2/5] $RC_FILE에서 pyenv 설정 제거...${NC}"
if [[ -f "$RC_FILE" ]]; then
    # 백업 생성
    cp "$RC_FILE" "${RC_FILE}.backup.$(date +%Y%m%d%H%M%S)"

    # pyenvrc, openpilot_env.sh 관련 줄 제거
    sed -i '/pyenvrc/d' "$RC_FILE"
    sed -i '/openpilot_env\.sh/d' "$RC_FILE"
    sed -i '/PYENV_ROOT/d' "$RC_FILE"
    sed -i '/pyenv init/d' "$RC_FILE"
    sed -i '/pyenv virtualenv-init/d' "$RC_FILE"

    echo -e " ↳ [${GREEN}✔${NC}] RC 파일 정리됨 (백업: ${RC_FILE}.backup.*)"
else
    echo -e " ↳ [${YELLOW}!${NC}] $RC_FILE 없음"
fi

# 3. pyenv 제거 (선택)
echo -e "${BOLD}[3/5] pyenv 제거...${NC}"
if [[ -d "$HOME/.pyenv" ]]; then
    read -p "pyenv를 완전히 삭제하시겠습니까? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf "$HOME/.pyenv"
        echo -e " ↳ [${GREEN}✔${NC}] ~/.pyenv 삭제됨"
    else
        echo -e " ↳ [${YELLOW}!${NC}] pyenv 유지됨"
    fi
else
    echo -e " ↳ [${YELLOW}!${NC}] ~/.pyenv 없음 (건너뜀)"
fi

# 4. poetry virtualenvs 제거
echo -e "${BOLD}[4/5] poetry 가상환경 제거...${NC}"
POETRY_VENV_DIR="$HOME/.cache/pypoetry/virtualenvs"
if [[ -d "$POETRY_VENV_DIR" ]]; then
    # openpilot 관련 virtualenv만 제거
    OPENPILOT_VENVS=$(ls -d "$POETRY_VENV_DIR"/openpilot-* 2>/dev/null || true)
    if [[ -n "$OPENPILOT_VENVS" ]]; then
        read -p "openpilot poetry 가상환경을 삭제하시겠습니까? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -rf "$POETRY_VENV_DIR"/openpilot-*
            echo -e " ↳ [${GREEN}✔${NC}] openpilot 가상환경 삭제됨"
        else
            echo -e " ↳ [${YELLOW}!${NC}] 가상환경 유지됨"
        fi
    else
        echo -e " ↳ [${YELLOW}!${NC}] openpilot 가상환경 없음"
    fi
else
    echo -e " ↳ [${YELLOW}!${NC}] poetry 가상환경 디렉토리 없음"
fi

# 5. openpilot 로컬 설정 파일 제거
echo -e "${BOLD}[5/5] openpilot 로컬 설정 제거...${NC}"
OPENPILOT_DIR="$(pwd)"
if [[ -f "$OPENPILOT_DIR/poetry.toml" ]]; then
    rm -f "$OPENPILOT_DIR/poetry.toml"
    echo -e " ↳ [${GREEN}✔${NC}] poetry.toml 삭제됨"
fi
if [[ -f "$OPENPILOT_DIR/.env" ]]; then
    rm -f "$OPENPILOT_DIR/.env"
    echo -e " ↳ [${GREEN}✔${NC}] .env 삭제됨"
fi

echo ""
echo "=================================="
echo -e "  ${GREEN}정리 완료${NC}"
echo "=================================="
echo ""
echo "변경사항을 적용하려면:"
echo "  source ~/.bashrc"
echo ""
echo "또는 새 터미널을 열어주세요."
echo ""
