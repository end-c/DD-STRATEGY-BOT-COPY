#!/usr/bin/env bash
set -euo pipefail

# 参数部分
KEY_PREFIX="${1:-}"
ACCOUNTS="${2:-}"
INTERVAL="${3:-0}"
STALL_SECONDS="${4:-180}"
ORDER_STABLE_SECONDS="${5:-180}"

# 检查必需的参数是否提供
if [ -z "$KEY_PREFIX" ] || [ -z "$ACCOUNTS" ]; then
    echo "Usage: $0 KEY_PREFIX ACCOUNTS [STALL_SECONDS] [ORDER_STABLE_SECONDS] [INTERVAL]"
    exit 1
fi


# 显示标题
echo "=== StandX STATUS + PANIC PANEL ==="

# 设置路径
SCRIPT_DIR=$(dirname "$0")
CODE_ROOT=$(dirname "$SCRIPT_DIR")

PROC_DIR="$CODE_ROOT/strategys/strategy_standx"
LOG_DIR="$CODE_ROOT/logs"
SNAP_DIR="$CODE_ROOT/snapshots"

PYTHON="python3" # 在MacOS上使用python3
DECRYPT="$PROC_DIR/decrypt_keys.py"
CANCEL_PY="$PROC_DIR/cancel_all_orders.py"
SNAPSHOT_PY="$PROC_DIR/snapshot_account.py"

# 创建快照目录
mkdir -p "$SNAP_DIR"

# 工具函数
parse_accounts() {
    local key_prefix=$1
    local acc_str=$2
    declare -a accounts
    IFS=',' read -ra ADDR <<< "$acc_str"
    for part in "${ADDR[@]}"; do
        if [[ "$part" =~ "-" ]]; then
            IFS="-" read -r start end <<< "$part"
            for ((i=start; i<=end; i++)); do
                accounts+=("${key_prefix}${i}")
            done
        else
            accounts+=("${key_prefix}${part}")
        fi
    done
    echo "${accounts[@]}"
}

read_last_log_time() {
    local log_file=$1
    if [[ -f "$log_file" ]]; then
        stat -f "%m" "$log_file"
    else
        echo ""
    fi
}

load_state() {
    local account_id=$1
    local state_file="$LOG_DIR/$account_id.state.json"
    if [[ -f "$state_file" ]]; then
        cat "$state_file"
    else
        echo '{"last_orders": -1, "last_change": 0}'
    fi
}

save_state() {
    local account_id=$1
    local json_data=$2
    local state_file="$LOG_DIR/$account_id.state.json"
    echo "$json_data" > "$state_file"
}

# 输入密码
echo "Enter vault password:"
read -s PASSWORD

# 解析账户
ACCOUNT_SET=($(parse_accounts "$KEY_PREFIX" "$ACCOUNTS"))

# 表头
printf "%-16s %-9s %-6s %-10s %-28s %s\n" "ACCOUNT" "STATUS" "PID" "ORDERS" "POSITION" "NOTE"
echo "--------------------------------------------------------------------------------------"

# 实时监控（watch）
monitor_accounts() {
    # 清空上次的终端输出
    clear

    # 表头
    printf "%-16s %-9s %-6s %-10s %-28s %s\n" "ACCOUNT" "STATUS" "PID" "ORDERS" "POSITION" "NOTE"
    echo "--------------------------------------------------------------------------------------"

    for accountId in "${ACCOUNT_SET[@]}"; do
        PID_FILE="$LOG_DIR/$accountId.pid"
        LOG_FILE="$LOG_DIR/$accountId.log"

        status="UNKNOWN"
        note="-"
        pidTxt="-"
        orders="ERR"
        posTxt="ERR"

        # ---------- 进程 ----------
        procAlive=false
        if [[ -f "$PID_FILE" ]]; then
            pid=$(cat "$PID_FILE")
            if ps -p "$pid" > /dev/null; then
                procAlive=true
                pidTxt="$pid"
            fi
        fi

        # ---------- 日志活跃度 ----------
        stallByLog=false
        lastLog=$(read_last_log_time "$LOG_FILE")
        if [[ -n "$lastLog" ]]; then
            delta=$(( $(date +%s) - lastLog ))
            if (( delta > STALL_SECONDS )); then
                stallByLog=true
            fi
        fi

        # ---------- 查询交易所状态 ----------
        snapshotOK=false
        snapshot=$(python3 "$SNAPSHOT_PY" --private_key "$(python3 "$DECRYPT" "$PASSWORD" "$KEY_PREFIX" "$(echo "$accountId" | grep -o '[0-9]*')" )" --account_id "$accountId" 2>/dev/null)

        if [[ -n "$snapshot" ]]; then
            data=$(echo "$snapshot" | jq -r '.')
            orders=$(echo "$data" | jq '.open_orders | length')
            posTxt=$(echo "$data" | jq -r '.position_summary')

            if [[ -z "$posTxt" ]]; then
                posTxt="flat"
            fi

            snapshotOK=true
        fi

        # ---------- STALLED（订单冻结）判定 ----------
        stallByOrders=false
        state=$(load_state "$accountId")
        last_orders=$(echo "$state" | jq '.last_orders')
        last_change=$(echo "$state" | jq '.last_change')
        now=$(date +%s)

        if [[ "$orders" =~ ^[0-9]+$ ]]; then
            if (( last_orders == orders )); then
                if (( now - last_change > ORDER_STABLE_SECONDS )); then
                    stallByOrders=true
                fi
            else
                new_state=$(echo "$state" | jq ".last_orders = $orders | .last_change = $now")
                save_state "$accountId" "$new_state"
            fi
        fi

        if [[ "$stallByLog" == true && "$stallByOrders" == true ]]; then
            stall=true
        else
            stall=false
        fi

        # ---------- 状态判定 ----------
        if [[ "$procAlive" == false ]]; then
            status="DEAD"
            note="process gone"
        elif [[ "$stall" == true ]]; then
            status="STALLED"
            note="orders frozen"
        else
            status="RUNNING"
        fi

        # 输出当前状态
        printf "%-16s %-9s %-6s %-10s %-28s %s\n" "$accountId" "$status" "$pidTxt" "$orders" "$posTxt" "$note"
    done
}

# ---------- 监控执行 ----------

if (( INTERVAL > 0 )); then
    # Watch模式，持续执行
    while true; do
        monitor_accounts
        sleep "$INTERVAL"
    done
else
    # 单次执行
    monitor_accounts
fi
