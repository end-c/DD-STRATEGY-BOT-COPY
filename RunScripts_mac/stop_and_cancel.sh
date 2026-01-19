#!/usr/bin/env bash
set -euo pipefail

#######################################
# 参数解析
#######################################
if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <KEY_PREFIX> <ACCOUNTS>"
  echo "Example: $0 account_hp 5-10"
  echo "Example: $0 account_hp 5,7,9"
  exit 1
fi

KEY_PREFIX="$1"
ACCOUNTS="$2"

echo "=== StandX STOP (SAFE MODE) ==="

#######################################
# 路径
#######################################
# 当前脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 项目根目录
CODE_ROOT="$(dirname "$SCRIPT_DIR")"

PROC_DIR="$CODE_ROOT/strategys/strategy_standx"

CANCEL_SCRIPT="$PROC_DIR/cancel_all_orders.py"
DECRYPT_SCRIPT="$PROC_DIR/decrypt_keys.py"

VENV_ROOT="$CODE_ROOT/venvs"
LOG_DIR="$CODE_ROOT/logs"
PYTHON="python3"

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
# 输入密码（隐藏）
#######################################
echo "Enter private key vault password:"
read -s PASSWORD
echo

ACCOUNT_SET=($(parse_accounts "$KEY_PREFIX" "$ACCOUNTS"))

if [ "${#ACCOUNT_SET[@]}" -eq 0 ]; then
  echo "No accounts resolved"
  exit 1
fi

echo "Stopping accounts: ${ACCOUNT_SET[*]}"

#######################################
# 主循环
#######################################
for accountId in "${ACCOUNT_SET[@]}"; do
  echo
  echo ">>> STOP $accountId"

  # 从 account_hp12 解析 index=12
  if [[ "$accountId" =~ ([0-9]+)$ ]]; then
    index="${BASH_REMATCH[1]}"
  else
    echo "Invalid account id: $accountId"
    continue
  fi

  PID_FILE="$LOG_DIR/$accountId.pid"
  VENV="$VENV_ROOT/venv_$accountId"
  PY_EXE="$VENV/bin/python"

  ###################################
  # 解密私钥
  ###################################
  private_key="$($PYTHON "$DECRYPT_SCRIPT" "$PASSWORD" "$KEY_PREFIX" "$index" || true)"

  if [ -z "$private_key" ]; then
    echo "decrypt failed"
    continue
  fi

  ###################################
  # 先 kill 策略进程
  ###################################
  if [ -f "$PID_FILE" ]; then
    procId="$(cat "$PID_FILE")"
    if ps -p "$procId" > /dev/null 2>&1; then
      kill -9 "$procId"
      echo "Killed PID $procId"
    fi
    rm -f "$PID_FILE"
  else
    echo "PID file not found"
  fi

  sleep 2

  ###################################
  # 再撤单
  ###################################
  if [ -x "$PY_EXE" ] && [ -f "$CANCEL_SCRIPT" ]; then
    echo "Cancel orders..."
    "$PY_EXE" "$CANCEL_SCRIPT" \
      --private_key "$private_key" \
      --account_id "$accountId"
  else
    echo "cancel skipped (python not found)"
  fi

  unset private_key
done

unset PASSWORD

echo
echo "=== StandX STOP DONE ==="
