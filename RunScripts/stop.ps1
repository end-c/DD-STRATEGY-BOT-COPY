# Get-ChildItem logs\*.pid | ForEach-Object {
#     $pid = Get-Content $_
#     if (Get-Process -Id $pid -ErrorAction SilentlyContinue) {
#         Stop-Process -Id $pid -Force
#         Write-Host "Killed PID $pid"
#     }
# }


# ==============================
# stop.ps1 - stop all strategy processes
# ==============================

Write-Host "=== StandX STOP ===" -ForegroundColor Cyan

# ---------- 定位脚本所在目录 ----------
$SCRIPT_DIR = $PSScriptRoot
if (-not $SCRIPT_DIR) {
    $SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
}

if (-not $SCRIPT_DIR) {
    Write-Error "Cannot determine script directory"
    exit 1
}

# RunScripts -> 项目根目录
$CODE_ROOT = Split-Path $SCRIPT_DIR -Parent
$LOG_DIR   = Join-Path $CODE_ROOT "logs"

if (!(Test-Path $LOG_DIR)) {
    Write-Warning "Log directory not found: $LOG_DIR"
    exit 0
}

# ---------- Kill by PID ----------
$pidFiles = Get-ChildItem "$LOG_DIR\*.pid" -ErrorAction SilentlyContinue

if (!$pidFiles) {
    Write-Host "No pid files found." -ForegroundColor Yellow
    exit 0
}

foreach ($file in $pidFiles) {
    $pid = Get-Content $file | Select-Object -First 1

    if ($pid -match '^\d+$') {
        $proc = Get-Process -Id $pid -ErrorAction SilentlyContinue
        if ($proc) {
            Stop-Process -Id $pid -Force
            Write-Host "Killed PID $pid ($($file.Name))" -ForegroundColor Green
        } else {
            Write-Host "PID $pid not running ($($file.Name))" -ForegroundColor DarkGray
        }
    }

    # 可选：删除 pid 文件
    Remove-Item $file -Force
}

Write-Host "=== STOP DONE ===" -ForegroundColor Cyan




# $proc = Start-Process `
#     -FilePath $PYTHON_EXE `
#     -ArgumentList "`"$PROC_SCRIPT`" --private_key $private_key --account_id $accountId" `
#     -WorkingDirectory $CODE_ROOT `
#     -NoNewWindow `
#     -PassThru

# $proc.Id | Out-File "$LOG_DIR\$accountId.pid" -Encoding ascii




        # taskkill /F /IM python.exe
        # taskkill /F /FI "WINDOWTITLE eq standx_mm_new.py*"
        # 确保没有残留 
        # tasklist | findstr python