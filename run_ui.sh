#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
export ENGINE_PATH="$ROOT_DIR/engine/target/release/engine"

UI_BIN="$ROOT_DIR/ui/.build/release/UIApp"
if [ ! -x "$UI_BIN" ]; then
  cd "$ROOT_DIR/ui"
  swift build -c release
fi

"$UI_BIN"
