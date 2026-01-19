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

echo "=== StandX Runner Started ==="
echo "Accounts arg: $ACCOUNTS"

#######################################
# 路径配置
#######################################
# 当前脚本所在目录（RunScripts）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 项目根目录
CODE_ROOT="$(dirname "$SCRIPT_DIR")"

# 策略目录
PROC_DIR="$CODE_ROOT/strategys/strategy_standx"
PROC_SCRIPT="$PROC_DIR/standx_mm_new.py"
PROC_SCRIPT_DECRYPT="$PROC_DIR/decrypt_keys.py"

VENV_ROOT="$CODE_ROOT/venvs"
LOG_DIR="$CODE_ROOT/logs"
PYTHON="python3"

mkdir -p "$VENV_ROOT" "$LOG_DIR"
cd "$CODE_ROOT"

#######################################
# 日志函数
#######################################
log() {
  local msg="$1"
  local logfile="$2"
  echo "$(date '+%Y-%m-%d %H:%M:%S') | $msg" | tee -a "$logfile"
}

#######################################
# 账户解析函数（5-10 / 5,7,9）
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
  echo "No accounts resolved from '$ACCOUNTS'"
  exit 1
fi

echo "Resolved accounts: ${ACCOUNT_SET[*]}"

#######################################
# 校验主脚本
#######################################
if [ ! -f "$PROC_SCRIPT" ]; then
  echo "Processing script not found: $PROC_SCRIPT"
  exit 1
fi

#######################################
# 主循环
#######################################
for accountId in "${ACCOUNT_SET[@]}"; do
  echo
  echo ">>> Running account $accountId"

  # 从 account_hp12 提取 index=12
  if [[ "$accountId" =~ ([0-9]+)$ ]]; then
    index="${BASH_REMATCH[1]}"
  else
    echo "Invalid account id: $accountId"
    continue
  fi

  VENV="$VENV_ROOT/venv_$accountId"
  LOG="$LOG_DIR/$accountId.log"
  PID_FILE="$LOG_DIR/$accountId.pid"

  log "===== START account=$accountId =====" "$LOG"

  ###################################
  # 解密私钥
  ###################################
  private_key="$($PYTHON "$PROC_SCRIPT_DECRYPT" "$PASSWORD" "$KEY_PREFIX" "$index" || true)"

  if [ -z "$private_key" ]; then
    echo "Failed to load private key for account $index"
    log "Private key not found" "$LOG"
    continue
  fi

  ###################################
  # 虚拟环境
  ###################################
  if [ ! -d "$VENV" ]; then
    log "Creating venv" "$LOG"
    $PYTHON -m venv "$VENV"
  fi

  PYTHON_EXE="$VENV/bin/python"
  PIP_EXE="$VENV/bin/pip"

  if [ ! -f "$VENV/.deps_installed" ]; then
    "$PIP_EXE" install -r "$CODE_ROOT/requirements.txt"
    touch "$VENV/.deps_installed"
  fi

  ###################################
  # 启动策略（后台）
  ###################################
  "$PYTHON_EXE" \
    "$PROC_SCRIPT" \
    --private_key "$private_key" \
    --account_id "$accountId" \
    >> "$LOG" 2>&1 &

  PID=$!
  echo "$PID" > "$PID_FILE"
  echo "Started $accountId (PID=$PID)"

  log "===== END index=$index =====" "$LOG"

  unset private_key
done

unset PASSWORD
