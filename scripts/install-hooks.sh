#!/usr/bin/env bash
# Corre una vez tras clonar: activa el escaneo de dominios/secretos
# hardcodeados en pre-commit y pre-push (.githooks/).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
git config core.hooksPath .githooks
echo "Hooks activados (core.hooksPath=.githooks)."
