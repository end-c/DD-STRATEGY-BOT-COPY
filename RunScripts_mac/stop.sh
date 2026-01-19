#!/usr/bin/env bash
set -euo pipefail

echo "=== StandX STOP ==="

#######################################
# 定位脚本所在目录
#######################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -z "$SCRIPT_DIR" ]; then
  echo "Cannot determine script directory"
  exit 1
fi

# RunScripts -> 项目根目录
CODE_ROOT="$(dirname "$SCRIPT_DIR")"
LOG_DIR="$CODE_ROOT/logs"

if [ ! -d "$LOG_DIR" ]; then
  echo "Log directory not found: $LOG_DIR"
  exit 0
fi

#######################################
# Kill by PID
#######################################
shopt -s nullglob
PID_FILES=("$LOG_DIR"/*.pid)
shopt -u nullglob

if [ "${#PID_FILES[@]}" -eq 0 ]; then
  echo "No pid files found."
  exit 0
fi

for pidFile in "${PID_FILES[@]}"; do
  procPid="$(head -n 1 "$pidFile" 2>/dev/null || true)"

  if [[ "$procPid" =~ ^[0-9]+$ ]]; then
    if ps -p "$procPid" > /dev/null 2>&1; then
      kill -9 "$procPid"
      echo "Killed PID $procPid ($(basename "$pidFile"))"
    else
      echo "PID $procPid not running ($(basename "$pidFile"))"
    fi
  fi

  # 删除 pid 文件
  rm -f "$pidFile"
done

echo "=== STOP DONE ==="
