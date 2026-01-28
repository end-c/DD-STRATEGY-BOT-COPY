param(
    [Parameter(Mandatory=$true)]
    [string]$KEY_PREFIX,

    [Parameter(Mandatory=$true)]
    [string]$ACCOUNTS,        # 5-10 / 5,7,9

    [int]$STALL_SECONDS = 180,
    [int]$ORDER_STABLE_SECONDS = 180,

    [int]$Interval = 0  # 设置间隔时间（秒），0为不间隔，执行一次后结束
)

[Console]::OutputEncoding = [Text.Encoding]::UTF8
chcp 65001 | Out-Null

Write-Host "=== StandX STATUS + PANIC PANEL ===" -ForegroundColor Cyan

# ---------- 路径 ----------

$SCRIPT_DIR = $PSScriptRoot
$CODE_ROOT  = Split-Path $SCRIPT_DIR -Parent

$PROC_DIR   = "$CODE_ROOT\strategys\strategy_standx"
$LOG_DIR    = "$CODE_ROOT\logs"

$PYTHON      = "python"
$DECRYPT     = "$PROC_DIR\decrypt_keys.py"

$SNAPSHOT_PY = "$PROC_DIR\snapshot_account.py"

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
Write-Host "=== StandX STATUS + PANIC PANEL ===" -ForegroundColor Cyan
Write-Host ""

"{0,-16} {1,-9} {2,-6} {3,-10} {4,-28} {5}" -f `  # 增加 posTxt 宽度为 -28
    "ACCOUNT","STATUS","PID","ORDERS","POSITION","NOTE"
Write-Host ("-" * 95)

# ---------- 实时监控（watch） ----------
function Monitor-Accounts {

    # 清空上次的终端输出
    Clear-Host

    # ---------- 表头 ----------
    "{0,-16} {1,-9} {2,-6} {3,-10} {4,-28} {5}" -f `  # 增加 posTxt 宽度为 -28
        "ACCOUNT","STATUS","PID","ORDERS","POSITION","NOTE"
    Write-Host ("-" * 95)

    foreach ($accountId in $ACCOUNT_SET) {

        $PID_FILE = "$LOG_DIR\$accountId.pid"
        $LOG_FILE = "$LOG_DIR\$accountId.log"

        $status = "UNKNOWN"
        $note   = "-"
        $pidTxt = "-"
        $orders = "ERR"
        $posTxt = "ERR"

        # ---------- 进程 ----------
        $procAlive = $false
        if (Test-Path $PID_FILE) {
            $procPid = Get-Content $PID_FILE -ErrorAction SilentlyContinue
            if ($procPid -and (Get-Process -Id $procPid -ErrorAction SilentlyContinue)) {
                $procAlive = $true
                $pidTxt = $procPid
            }
        }

        # ---------- 日志活跃度 ----------
        $stallByLog = $false
        $lastLog = Read-LastLogTime $LOG_FILE
        if ($lastLog) {
            $delta = (New-TimeSpan -Start $lastLog -End (Get-Date)).TotalSeconds
            if ($delta -gt $STALL_SECONDS) {
                $stallByLog = $true
            }
        }

        # ---------- 查询交易所状态（无论本地是否存活） ----------
        $snapshotOK = $false
        try {
            $index = ($accountId -replace ".*?(\d+)$",'$1')
            $private_key = & $PYTHON $DECRYPT $PASSWORD $KEY_PREFIX $index

            $snapshot = & $PYTHON $SNAPSHOT_PY `
                --private_key $private_key `
                --account_id  $accountId `
                2>$null

            if ($snapshot) {
                $data   = $snapshot | ConvertFrom-Json
                # $orders = [int]$data.open_orders
                $orders = 0
                if ($data.open_orders) {
                    $orders = @($data.open_orders).Count
                }
                # $posTxt = $data.position_summary
                $posTxt = $data.position_summary
                if (-not $posTxt) {
                    $posTxt = "flat"
                }

                $snapshotOK = $true
            }
        }
        catch {
            $orders = "ERR"
            $posTxt = "ERR"
        }

        # ---------- STALLED（订单冻结）判定 ----------
        $stallByOrders = $false
        $state = Load-State $accountId
        $now = [int][double]::Parse((Get-Date -UFormat %s))

        if ($orders -is [int]) {
            if ($state.last_orders -eq $orders) {
                if (($now - $state.last_change) -gt $ORDER_STABLE_SECONDS) {
                    $stallByOrders = $true
                }
            } else {
                $state.last_orders = $orders
                $state.last_change = $now
            }
            Save-State $accountId $state
        }

        $stall = $stallByLog -and $stallByOrders

        # ---------- 状态判定 ----------
        if (!$procAlive) {
            $status = "DEAD"
            $note   = "process gone"
        }
        elseif ($stall) {
            $status = "STALLED"
            $note   = "orders frozen"
        }
        else {
            $status = "RUNNING"
        }

        "{0,-16} {1,-9} {2,-6} {3,-10} {4,-28} {5}" -f `  # 增加 posTxt 宽度为 -28
            $accountId,$status,$pidTxt,$orders,$posTxt,$note
    }
}

# ---------- 监控执行 ----------

if ($Interval -gt 0) {
    # Watch模式，持续执行
    while ($true) {
        Monitor-Accounts
        Start-Sleep -Seconds $Interval
    }
} else {
    # 单次执行
    Monitor-Accounts
}

Remove-Variable PASSWORD -ErrorAction SilentlyContinue
