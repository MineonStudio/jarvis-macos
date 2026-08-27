#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec env JARVIS_DEV_BUILD=1 "$ROOT_DIR/build_app.sh" "$@"
