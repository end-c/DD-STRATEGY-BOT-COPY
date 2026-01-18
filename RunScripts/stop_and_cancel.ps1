param(
    [Parameter(Mandatory=$true)]
    [string]$KEY_PREFIX,

    [Parameter(Mandatory=$true)]
    [string]$ACCOUNTS   # 5-10 或 5,7,9
)

[Console]::OutputEncoding = [Text.Encoding]::UTF8
chcp 65001 | Out-Null

Write-Host "=== StandX STOP (SAFE MODE) ===" -ForegroundColor Cyan

# ---------- 路径 ----------
$SCRIPT_DIR = $PSScriptRoot
$CODE_ROOT  = Split-Path $SCRIPT_DIR -Parent
$PROC_DIR   = "$CODE_ROOT\strategys\strategy_standx"

$CANCEL_SCRIPT = "$PROC_DIR\cancel_all_orders.py"
$DECRYPT_SCRIPT = "$PROC_DIR\decrypt_keys.py"

$VENV_ROOT = "$CODE_ROOT\venvs"
$LOG_DIR   = "$CODE_ROOT\logs"
$PYTHON    = "python"

# ---------- 工具 ----------
function Parse-Accounts($prefix, $s) {
    $set = New-Object System.Collections.Generic.HashSet[string]
    foreach ($part in $s.Split(",")) {
        if ($part -match "-") {
            $a, $b = $part.Split("-", 2)
            for ($i = [int]$a; $i -le [int]$b; $i++) {
                $set.Add("$prefix$i") | Out-Null
            }
        } else {
            $set.Add("$prefix$($part.Trim())") | Out-Null
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
if ($ACCOUNT_SET.Count -eq 0) {
    Write-Error "No accounts resolved"
    exit 1
}

Write-Host "Stopping accounts: $($ACCOUNT_SET -join ', ')" -ForegroundColor Yellow

# ---------- 主循环 ----------
foreach ($accountId in $ACCOUNT_SET) {

    Write-Host "`n>>> STOP $accountId" -ForegroundColor Green

    if ($accountId -notmatch "(\d+)$") {
        Write-Host "Invalid account id: $accountId" -ForegroundColor Red
        continue
    }

    $index = $Matches[1]
    $PID_FILE = "$LOG_DIR\$accountId.pid"
    $VENV     = "$VENV_ROOT\venv_$accountId"
    $PY_EXE   = "$VENV\Scripts\python.exe"

    try {
        # ---- 解密私钥 ----
        $private_key = & $PYTHON $DECRYPT_SCRIPT `
            $PASSWORD $KEY_PREFIX $index

        if ($LASTEXITCODE -ne 0 -or !$private_key) {
            Write-Host "❌ decrypt failed" -ForegroundColor Red
            continue
        }

        # ---- 撤单（吞掉所有输出）----
        if (Test-Path $PY_EXE -and (Test-Path $CANCEL_SCRIPT)) {
            Write-Host "Cancel orders..."
            & $PY_EXE $CANCEL_SCRIPT `
                --private_key $private_key `
                --account_id  $accountId `
                *> $null
        } else {
            Write-Host "⚠ cancel skipped (python not found)" -ForegroundColor Yellow
        }

        # ---- Kill 策略进程 ----
        if (Test-Path $PID_FILE) {
            $procId = Get-Content $PID_FILE
            if ($procId -and (Get-Process -Id $procId -ErrorAction SilentlyContinue)) {
                Stop-Process -Id $procId -Force
                Write-Host "Killed PID $procId"
            }
            Remove-Item $PID_FILE -Force -ErrorAction SilentlyContinue
        } else {
            Write-Host "PID file not found"
        }

    } finally {
        Remove-Variable private_key -ErrorAction SilentlyContinue
    }
}

Remove-Variable PASSWORD -ErrorAction SilentlyContinue

Write-Host "`n=== StandX STOP DONE ===" -ForegroundColor Cyan
