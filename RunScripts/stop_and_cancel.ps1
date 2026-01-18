param(
    [Parameter(Mandatory=$true)]
    [string]$KEY_PREFIX,
    [Parameter(Mandatory=$true)]
    [string]$ACCOUNTS   # 5-10 或 5,7,9
    
)

[Console]::OutputEncoding = [Text.Encoding]::UTF8
chcp 65001 | Out-Null

Write-Host "=== StandX STOP Started ===" -ForegroundColor Cyan
Write-Host "Accounts arg: $ACCOUNTS"

# ---------- 全局配置 ----------
$CANCEL_FAILED = @()
$CANCEL_SKIPPED = @()

# 当前脚本所在目录（RunScripts）
$SCRIPT_DIR = $PSScriptRoot

# 项目根目录
$CODE_ROOT = Split-Path $SCRIPT_DIR -Parent

# 策略所在目录
$PROC_DIR  = "$CODE_ROOT\strategys\strategy_standx"
$CANCEL_SCRIPT = "$PROC_DIR\cancel_all_orders.py"

$PROC_SCRIPT_decrypt = "$PROC_DIR\decrypt_keys.py"

$VENV_ROOT = "$CODE_ROOT\venvs"
$LOG_DIR   = "$CODE_ROOT\logs"
$PYTHON    = "python"

$MAX_RETRY = 3
$RETRY_WAIT = 5

Set-Location $CODE_ROOT
New-Item $VENV_ROOT -ItemType Directory -Force | Out-Null
New-Item $LOG_DIR -ItemType Directory -Force | Out-Null

# ---------- 工具函数 ----------
function Log($msg, $logfile) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts | $msg" | Tee-Object -FilePath $logfile -Append
}

function Parse-Accounts($keyPrefix, $s) {
    $set = New-Object System.Collections.Generic.HashSet[string]

    foreach ($part in $s.Split(",")) {
        if ($part -match "-") {
            $a, $b = $part.Split("-", 2)
            for ($i = [int]$a; $i -le [int]$b; $i++) {
                $set.Add("$keyPrefix$i") | Out-Null
            }
        } else {
            $set.Add("$keyPrefix$($part.Trim())") | Out-Null
        }
    }
    return $set
}

# ---------- 输入密码 ----------
Write-Host "Enter private key vault password:" -ForegroundColor Yellow
$PASSWORD_SEC = Read-Host -AsSecureString
$PASSWORD = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($PASSWORD_SEC)
)

$ACCOUNT_SET = Parse-Accounts $KEY_PREFIX $ACCOUNTS

if (-not $ACCOUNT_SET -or $ACCOUNT_SET.Count -eq 0) {
    Write-Error "No accounts resolved from '$ACCOUNTS'"
    exit 1
}

Write-Host "Resolved accounts: $($ACCOUNT_SET -join ', ')" -ForegroundColor Yellow


if (!(Test-Path $CANCEL_SCRIPT)) {
    Write-Error "Processing script not found: $CANCEL_SCRIPT"
    exit 1
}

# ---------- 主循环 ----------
foreach ($accountId in $ACCOUNT_SET) {

    Write-Host "`n>>> STOP $accountId" -ForegroundColor Green

    # 从 account_hp12 解析 index = 12
    if ($accountId -match "(\d+)$") {
        $index = $Matches[1]
    } else {
        Write-Host "Invalid account id: $accountId" -ForegroundColor Red
        continue
    }

    $LOG = "$LOG_DIR\$accountId.log"
    $PID_FILE = "$LOG_DIR\$accountId.pid"
    $VENV = "$VENV_ROOT\venv_$accountId"
    $PYTHON_EXE = "$VENV\Scripts\python.exe"

    Log "===== START account=$accountId =====" $LOG

    try {
        # ---- 解密单个私钥（只存在于此作用域）----
        $private_key = & $PYTHON "$PROC_SCRIPT_decrypt" "$PASSWORD" "$KEY_PREFIX" "$index"
        
        if ($LASTEXITCODE -ne 0 -or !$private_key) {
            Write-Host "Failed to load private key for account $index" -ForegroundColor Red
            Log "Private key not found" $LOG
            continue
        }

        # ---- 撤单（同步执行）----
        if (Test-Path $PYTHON_EXE) {

            Log "Cancel all orders..." $LOG

            & $PYTHON_EXE $CANCEL_SCRIPT `
                --private_key $private_key `
                --account_id $accountId `
                >> $LOG 2>&1

            if ($LASTEXITCODE -ne 0) {
                Log "Cancel orders FAILED (exit=$LASTEXITCODE)" $LOG
                $CANCEL_FAILED += $accountId
            } else {
                Log "Cancel orders SUCCESS" $LOG
            }

        } else {
            Log "Python venv not found, cancel skipped" $LOG
            $CANCEL_SKIPPED += $accountId
        }

        # ---- Kill 运行中的策略进程 ----
        if (Test-Path $PID_FILE) {
            $pid = Get-Content $PID_FILE
            if (Get-Process -Id $pid -ErrorAction SilentlyContinue) {
                Stop-Process -Id $pid -Force
                Log "Killed PID $pid" $LOG
            }
            Remove-Item $PID_FILE -Force
        } else {
            Log "PID file not found" $LOG
        }

    } finally {
        Remove-Variable private_key -ErrorAction SilentlyContinue
        Log "===== STOP END account=$accountId =====`n" $LOG
    }
}

Remove-Variable PASSWORD -ErrorAction SilentlyContinue

Write-Host "`n========== CANCEL SUMMARY ==========" -ForegroundColor Cyan

if ($CANCEL_FAILED.Count -gt 0) {
    Write-Host "ancel FAILED accounts:" -ForegroundColor Red
    $CANCEL_FAILED | ForEach-Object {
        Write-Host "  - $_" -ForegroundColor Red
    }
} else {
    Write-Host "No cancel failures" -ForegroundColor Green
}

if ($CANCEL_SKIPPED.Count -gt 0) {
    Write-Host "`n⚠ Cancel SKIPPED accounts (no venv/python):" -ForegroundColor Yellow
    $CANCEL_SKIPPED | ForEach-Object {
        Write-Host "  - $_" -ForegroundColor Yellow
    }
}

Write-Host "=== StandX STOP Completed ===" -ForegroundColor Cyan