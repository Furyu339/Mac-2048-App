#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"

cd "$ROOT_DIR/engine"
~/.cargo/bin/cargo build --release

cd "$ROOT_DIR/ui"
swift build -c release

echo "Build complete"
