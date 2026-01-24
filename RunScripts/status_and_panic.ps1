param(
    [Parameter(Mandatory=$true)]
    [string]$KEY_PREFIX,

    [Parameter(Mandatory=$true)]
    [string]$ACCOUNTS,        # 5-10 / 5,7,9

    [int]$STALL_SECONDS = 180,
    [int]$ORDER_STABLE_SECONDS = 180
)

[Console]::OutputEncoding = [Text.Encoding]::UTF8
chcp 65001 | Out-Null

Write-Host "=== StandX STATUS + PANIC PANEL ===" -ForegroundColor Cyan

# ---------- 路径 ----------
$SCRIPT_DIR = $PSScriptRoot
$CODE_ROOT  = Split-Path $SCRIPT_DIR -Parent

$PROC_DIR   = "$CODE_ROOT\strategys\strategy_standx"
$LOG_DIR    = "$CODE_ROOT\logs"
$SNAP_DIR   = "$CODE_ROOT\snapshots"

$PYTHON     = "python"
$DECRYPT    = "$PROC_DIR\decrypt_keys.py"
$CANCEL_PY  = "$PROC_DIR\cancel_all_orders.py"
$SNAPSHOT_PY= "$PROC_DIR\snapshot_account.py"

New-Item $SNAP_DIR -ItemType Directory -Force | Out-Null

# ---------- 工具 ----------
function Parse-Accounts($keyPrefix, $s) {
    $set = New-Object System.Collections.Generic.HashSet[string]
    foreach ($part in $s.Split(",")) {
        if ($part -match "-") {
            $a,$b = $part.Split("-",2)
            for ($i=[int]$a;$i -le [int]$b;$i++){
                $set.Add("$keyPrefix$i") | Out-Null
            }
        } else {
            $set.Add("$keyPrefix$($part.Trim())") | Out-Null
        }
    }
    return $set
}

function Read-LastLogTime($log) {
    if (!(Test-Path $log)) { return $null }
    return (Get-Item $log).LastWriteTime
}

function Load-State($accountId) {
    $f = "$LOG_DIR\$accountId.state.json"
    if (Test-Path $f) {
        return Get-Content $f | ConvertFrom-Json
    }
    return @{ last_orders = -1; last_change = 0 }
}

function Save-State($accountId, $obj) {
    $f = "$LOG_DIR\$accountId.state.json"
    $obj | ConvertTo-Json | Out-File $f -Encoding UTF8
}

# ---------- 输入密码 ----------
Write-Host "Enter vault password:" -ForegroundColor Yellow
$PASSWORD_SEC = Read-Host -AsSecureString
$PASSWORD = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($PASSWORD_SEC)
)

$ACCOUNT_SET = Parse-Accounts $KEY_PREFIX $ACCOUNTS

# ---------- 表头 ----------
"{0,-16} {1,-9} {2,-6} {3,-10} {4,-10} {5}" -f `
    "ACCOUNT","STATUS","PID","ORDERS","POSITION","NOTE"
Write-Host ("-" * 90)

foreach ($accountId in $ACCOUNT_SET) {

    $PID_FILE = "$LOG_DIR\$accountId.pid"
    $LOG_FILE = "$LOG_DIR\$accountId.log"

    $status = "DEAD"
    $note   = "-"
    $pidTxt = "-"
    $orders = "-"
    $posTxt = "-"

    # ---------- 进程 ----------
    $procAlive = $false
    if (Test-Path $PID_FILE) {
        $procPid = Get-Content $PID_FILE -ErrorAction SilentlyContinue
        if ($procPid -and (Get-Process -Id $procPid -ErrorAction SilentlyContinue)) {
            $procAlive = $true
            $pidTxt = $procPid
        }
    }

    if (!$procAlive) {
        "{0,-16} {1,-9} {2,-6} {3,-10} {4,-10} {5}" -f `
            $accountId,"DEAD",$pidTxt,$orders,$posTxt,"process gone"
        continue
    }

    # ---------- 日志活跃度 ----------
    $lastLog = Read-LastLogTime $LOG_FILE
    $stall = $false
    if ($lastLog) {
        $delta = (New-TimeSpan -Start $lastLog -End (Get-Date)).TotalSeconds
        if ($delta -gt $STALL_SECONDS) {
            $stall = $true
        }
    }

    # ---------- 查询账户状态（orders + positions） ----------
    try {
        $index = ($accountId -replace ".*?(\d+)$",'$1')
        $private_key = & $PYTHON $DECRYPT $PASSWORD $KEY_PREFIX $index

        $snapshot = & $PYTHON $SNAPSHOT_PY `
            --private_key $private_key `
            --account_id  $accountId `
            2>$null

        $data = $snapshot | ConvertFrom-Json
        $orders = $data.open_orders
        $posTxt = $data.position_summary

    } catch {
        $status = "ERROR"
        $note = "query failed"
    }

    # ---------- STALLED 判定 ----------
    $state = Load-State $accountId
    $now = [int][double]::Parse((Get-Date -UFormat %s))

    if ($state.last_orders -eq $orders) {
        if (($now - $state.last_change) -gt $ORDER_STABLE_SECONDS) {
            $stall = $true
        }
    } else {
        $state.last_orders = $orders
        $state.last_change = $now
    }

    Save-State $accountId $state

    if ($stall) {
        $status = "STALLED"
        $note = "orders not moving"
    } else {
        $status = "RUNNING"
    }

    # ---------- PANIC ----------
    if ($status -eq "STALLED") {
        Write-Host "PANIC → $accountId" -ForegroundColor Red

        $ts = Get-Date -Format "yyyyMMdd_HHmmss"
        & $PYTHON $SNAPSHOT_PY `
            --private_key $private_key `
            --account_id $accountId `
            > "$SNAP_DIR\$accountId.$ts.json"

        & $PYTHON $CANCEL_PY `
            --private_key $private_key `
            --account_id $accountId `
            *> $null

        Stop-Process -Id $procPid -Force -ErrorAction SilentlyContinue
        Remove-Item $PID_FILE -ErrorAction SilentlyContinue
    }

    "{0,-16} {1,-9} {2,-6} {3,-10} {4,-10} {5}" -f `
        $accountId,$status,$pidTxt,$orders,$posTxt,$note
}

Remove-Variable PASSWORD -ErrorAction SilentlyContinue
