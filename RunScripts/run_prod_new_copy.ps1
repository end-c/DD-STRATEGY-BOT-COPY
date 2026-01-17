param(
    [Parameter(Mandatory=$true)]
    [string]$KEY_PREFIX,
    [Parameter(Mandatory=$true)]
    [string]$ACCOUNTS   # 5-10 或 5,7,9
    
)

[Console]::OutputEncoding = [Text.Encoding]::UTF8
chcp 65001 | Out-Null

Write-Host "=== StandX Runner Started ===" -ForegroundColor Cyan
Write-Host "Accounts arg: $ACCOUNTS"

# ---------- 全局配置 ----------
# 当前脚本所在目录（RunScripts）
if ($PSScriptRoot) {
    $SCRIPT_DIR = $PSScriptRoot
} else {
    $SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
}

if (-not $SCRIPT_DIR) {
    Write-Error "Cannot determine script directory"
    exit 1
}

# 项目根目录
$CODE_ROOT = Split-Path $SCRIPT_DIR -Parent

# 策略所在目录
$PROC_DIR  = "$CODE_ROOT\strategys\strategy_standx"
$PROC_SCRIPT = "$PROC_DIR\standx_mm_new.py"


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


if (!(Test-Path $PROC_SCRIPT)) {
    Write-Error "Processing script not found: $PROC_SCRIPT"
    exit 1
}

# ---------- 主循环 ----------
foreach ($accountId in $ACCOUNT_SET) {

    Write-Host "`n>>> Running account $accountId" -ForegroundColor Green

    # 从 account_hp12 解析 index = 12
    if ($accountId -match "(\d+)$") {
        $index = $Matches[1]
    } else {
        Write-Host "Invalid account id: $accountId" -ForegroundColor Red
        continue
    }

    $VENV = "$VENV_ROOT\venv_$accountId"
    $LOG  = "$LOG_DIR\$accountId.log"

    Log "===== START account=$accountId =====" $LOG

    try {
        # ---- 解密单个私钥（只存在于此作用域）----
        $private_key = & $PYTHON "$PROC_SCRIPT_decrypt" "$PASSWORD" "$KEY_PREFIX" "$index"
        
        if ($LASTEXITCODE -ne 0 -or !$private_key) {
            Write-Host "Failed to load private key for account $index" -ForegroundColor Red
            Log "Private key not found" $LOG
            continue
        }

        # ---- venv ----
        if (!(Test-Path $VENV)) {
            Log "Creating venv" $LOG
            & $PYTHON -m venv $VENV
        }

        $PYTHON_EXE = "$VENV\Scripts\python.exe"
        $PIP_EXE = "$VENV\Scripts\pip.exe"

        if (!(Test-Path "$VENV\.deps_installed")) {
            & $PIP_EXE install -r "$CODE_ROOT\requirements.txt"
            if ($LASTEXITCODE -ne 0) {
                Write-Host "pip install failed, aborting account $index" -ForegroundColor Red
                continue
            }
            New-Item "$VENV\.deps_installed" -ItemType File | Out-Null
        }

        # ---- 执行策略 ----
        if (!(Test-Path $PYTHON_EXE)) {
            Log "Python exe not found in venv" $LOG
            continue
        }

        Start-Process `
            -FilePath $PYTHON_EXE `
            -ArgumentList "`"$PROC_SCRIPT`" --private_key $private_key --account_id $accountId" `
            -WorkingDirectory $CODE_ROOT `
            -NoNewWindow

    } finally {
        Remove-Variable private_key -ErrorAction SilentlyContinue
        Log "===== END index=$index =====`n" $LOG
    }
}

Remove-Variable PASSWORD -ErrorAction SilentlyContinue