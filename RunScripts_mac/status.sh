#!/usr/bin/env bash
set -euo pipefail

#######################################
# 参数解析
#######################################
# 用法：
# ./run_status.sh <KEY_PREFIX> [ACCOUNTS] [WATCH_SECONDS]
#
# ACCOUNTS:
#   12-14 / 12,15 / 不传 = 全部
#
# WATCH_SECONDS:
#   >0 进入刷新模式
#######################################

KEY_PREFIX="${1:-}"
ACCOUNTS="${2:-}"
WATCH="${3:-0}"

if [ -z "$KEY_PREFIX" ]; then
  echo "Usage: $0 <KEY_PREFIX> [ACCOUNTS] [WATCH_SECONDS]"
  exit 1
fi

#######################################
# 路径
#######################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODE_ROOT="$(dirname "$SCRIPT_DIR")"
LOG_DIR="$CODE_ROOT/logs"

# 超过多少秒没写 log 认为异常
LOG_STALE_SECONDS=120

#######################################
# 工具函数：解析账户
#######################################
parse_accounts() {
  local prefix="$1"
  local input="$2"
  local result=()

  IFS=',' read -ra parts <<< "$input"
  for part in "${parts[@]}"; do
    if [[ "$part" == *"-"* ]]; then
      IFS='-' read -r a b <<< "$part"
      for ((i=a; i<=b; i++)); do
        result+=("${prefix}${i}")
      done
    else
      result+=("${prefix}${part}")
    fi
  done

  echo "${result[@]}"
}

#######################################
# 主循环
#######################################
while :; do

  clear
  echo "=== StandX STATUS PANEL === $(date '+%H:%M:%S')"
  echo

  if [ -n "$ACCOUNTS" ]; then
    ACCOUNT_SET=($(parse_accounts "$KEY_PREFIX" "$ACCOUNTS"))
  else
    ACCOUNT_SET=()
    for f in "$LOG_DIR"/"$KEY_PREFIX"*.log; do
      [ -e "$f" ] || continue
      ACCOUNT_SET+=("$(basename "$f" .log)")
    done
  fi

  if [ "${#ACCOUNT_SET[@]}" -eq 0 ]; then
    echo "No accounts found"
    break
  fi

  printf "%-18s %-10s %-8s %-19s %s\n" \
    "ACCOUNT" "STATUS" "PID" "LAST LOG" "LAST MESSAGE"
  printf "%0.s-" {1..90}
  echo

  for accountId in "${ACCOUNT_SET[@]}"; do

    PID_FILE="$LOG_DIR/$accountId.pid"
    LOG_FILE="$LOG_DIR/$accountId.log"

    status="STOPPED"
    pidText="-"
    lastTime="-"
    lastMsg="-"

    procPid=""
    procAlive=false

    if [ -f "$PID_FILE" ]; then
      procPid="$(cat "$PID_FILE" 2>/dev/null || true)"
      if [ -n "$procPid" ] && ps -p "$procPid" > /dev/null 2>&1; then
        procAlive=true
      fi
    fi

    if $procAlive; then
      status="RUNNING"
      pidText="$procPid"
    fi

    if [ -f "$LOG_FILE" ]; then
      lastTime="$(stat -f '%Sm' -t '%m-%d %H:%M:%S' "$LOG_FILE")"
      lastMsg="$(tail -n 1 "$LOG_FILE" 2>/dev/null | cut -c1-40)"

      now=$(date +%s)
      logTime=$(stat -f '%m' "$LOG_FILE")
      age=$(( now - logTime ))

      if $procAlive && [ "$age" -gt "$LOG_STALE_SECONDS" ]; then
        status="STALLED"
      fi
    fi

    if [ -f "$PID_FILE" ] && ! $procAlive; then
      status="ZOMBIE"
      pidText="dead"
    fi

    printf "%-18s %-10s %-8s %-19s %s\n" \
      "$accountId" "$status" "$pidText" "$lastTime" "$lastMsg"
  done

  if [ "$WATCH" -gt 0 ]; then
    sleep "$WATCH"
  else
    break
  fi

done
