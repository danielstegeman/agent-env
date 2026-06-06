#!/usr/bin/env bash
# apmenv setup - source this from .bashrc / .zshrc:
#   source ~/apm-env-wrapper/setup.sh

APMENV_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

apmenv() {
    bash "${APMENV_DIR}/apmenv.sh" "$@"
}

export -f apmenv
