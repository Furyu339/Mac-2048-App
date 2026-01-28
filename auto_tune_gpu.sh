#!/bin/zsh
set -euo pipefail

ROOT="/Users/furyu/Desktop/2048-b-project"
UI_SRC="$ROOT/ui/Sources/UIApp"
APP="$ROOT/UIApp.app"
LOG="/tmp/auto_tune_gpu.log"
TARGET=50
MAX_ITERS=8192

log() { echo "[$(date +"%H:%M:%S")] $*" | tee -a "$LOG"; }

update_iters() {
  local iters="$1"
  python3 - "$iters" <<'PY'
import re, sys
from pathlib import Path
iters = int(sys.argv[1])

p = Path("/Users/furyu/Desktop/2048-b-project/ui/Sources/UIApp/GPUWorkload.swift")
text = p.read_text()
text = re.sub(r"iterations: \d+", f"iterations: {iters}", text)
p.write_text(text)

p2 = Path("/Users/furyu/Desktop/2048-b-project/ui/Sources/UIApp/HybridEvaluator.swift")
text2 = p2.read_text()
text2 = re.sub(r"iterations: \d+", f"iterations: {max(32, iters//8)}", text2)
p2.write_text(text2)
PY
}

build_and_update() {
  log "构建 UI…"
  (cd "$ROOT/ui" && swift build -c release)
  cp "$ROOT/ui/.build/release/UIApp" "$APP/Contents/MacOS/UIApp"
}

restart_app() {
  pkill -x UIApp || true
  # 使用可执行文件直接启动，避免 LSOpen 错误
  "$APP/Contents/MacOS/UIApp" >/dev/null 2>&1 &
  # wait for app + engine
  for _ in {1..30}; do
    if pgrep -x UIApp >/dev/null && pgrep -x engine >/dev/null; then
      return
    fi
    sleep 0.5
  done
}

read_gpu() {
  sudo powermetrics --samplers gpu_power -n 1 > /tmp/gpu_power.txt
  python3 - <<'PY'
import re
text = open('/tmp/gpu_power.txt').read()
m = re.search(r"GPU HW active residency:\s*([0-9.]+)%", text)
print(m.group(1) if m else "0")
PY
}

read_cpu() {
  python3 - <<'PY'
import subprocess
out = subprocess.check_output(["ps","-axo","pid,pcpu,comm"]).decode()
lines = [l for l in out.splitlines() if "UIApp.app" in l or "UIApp.app/engine" in l]
print("\n".join(lines) if lines else "no process")
PY
}

log "开始自动调参，目标 GPU >= ${TARGET}%"
log "日志：$LOG"
log "需要 sudo 权限，请输入密码（用于 GPU 采样）…"
# 先校验 sudo，之后保持有效
sudo -v
# 保持 sudo 有效
(while true; do sudo -n true; sleep 30; done) 2>/dev/null &
SUDO_KEEPALIVE_PID=$!
trap 'kill $SUDO_KEEPALIVE_PID >/dev/null 2>&1 || true' EXIT

iters=1024
while [ $iters -le $MAX_ITERS ]; do
  log "迭代次数 = $iters"
  update_iters "$iters"
  build_and_update
  restart_app
  log "采样 CPU…"
  read_cpu | tee -a "$LOG"
  log "采样 GPU…"
  gpu=$(read_gpu)
  log "GPU active = ${gpu}%"

  if python3 - <<PY
import sys
try:
    val = float("$gpu")
except:
    val = 0.0
sys.exit(0 if val >= $TARGET else 1)
PY
  then
    log "达标，停止调参"
    exit 0
  fi

  iters=$((iters*2))
  log "未达标，提升迭代为 $iters"
  sleep 1
done

log "已到最大迭代仍未达标"
exit 1
