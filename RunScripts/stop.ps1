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
    $procPid = Get-Content $file | Select-Object -First 1

    if ($procPid -match '^\d+$') {
        $proc = Get-Process -Id $procPid -ErrorAction SilentlyContinue
        if ($proc) {
            Stop-Process -Id $procPid -Force
            Write-Host "Killed PID $procPid ($($file.Name))" -ForegroundColor Green
        } else {
            Write-Host "PID $procPid not running ($($file.Name))" -ForegroundColor DarkGray
        }
    }

    # 可选：删除 pid 文件
    Remove-Item $file -Force
}

Write-Host "=== STOP DONE ===" -ForegroundColor Cyan









        # taskkill /F /IM python.exe
        # taskkill /F /FI "WINDOWTITLE eq standx_mm_new.py*"
        # 确保没有残留 
        # tasklist | findstr python