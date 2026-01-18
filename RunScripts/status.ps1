param(
    [Parameter(Mandatory=$true)]
    [string]$KEY_PREFIX,

    # 可选：12-14 / 12,15 / 不传 = 全部
    [string]$ACCOUNTS
)

[Console]::OutputEncoding = [Text.Encoding]::UTF8
chcp 65001 | Out-Null

Write-Host "=== StandX STATUS PANEL ===" -ForegroundColor Cyan

# ---------- 路径 ----------
$SCRIPT_DIR = $PSScriptRoot
$CODE_ROOT  = Split-Path $SCRIPT_DIR -Parent
$LOG_DIR    = "$CODE_ROOT\logs"

# ---------- 工具 ----------
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

# ---------- 账户集合 ----------
if ($ACCOUNTS) {
    $ACCOUNT_SET = Parse-Accounts $KEY_PREFIX $ACCOUNTS
} else {
    $ACCOUNT_SET = Get-ChildItem "$LOG_DIR\$KEY_PREFIX*.log" -ErrorAction SilentlyContinue |
        ForEach-Object {
            [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
        }
}

if (-not $ACCOUNT_SET -or $ACCOUNT_SET.Count -eq 0) {
    Write-Error "No accounts found"
    exit 1
}

# ---------- 表头 ----------
"{0,-18} {1,-8} {2,-8} {3,-20} {4}" -f `
    "ACCOUNT", "RUNNING", "PID", "LAST LOG", "LAST MESSAGE"
Write-Host ("-" * 90)

# ---------- 主循环 ----------
foreach ($accountId in $ACCOUNT_SET) {

    $PID_FILE = "$LOG_DIR\$accountId.pid"
    $LOG_FILE = "$LOG_DIR\$accountId.log"

    $running = "NO"
    $pidText = "-"
    $lastLogTime = "-"
    $lastMsg = "-"

    if (Test-Path $PID_FILE) {
        $pid = Get-Content $PID_FILE -ErrorAction SilentlyContinue
        if ($pid -and (Get-Process -Id $pid -ErrorAction SilentlyContinue)) {
            $running = "YES"
            $pidText = $pid
        } else {
            $pidText = "dead"
        }
    }

    if (Test-Path $LOG_FILE) {
        $lastLogTime = (Get-Item $LOG_FILE).LastWriteTime.ToString("MM-dd HH:mm:ss")

        $lastLine = Get-Content $LOG_FILE -Tail 1 -ErrorAction SilentlyContinue
        if ($lastLine) {
            $lastMsg = $lastLine.Substring(0, [Math]::Min(40, $lastLine.Length))
        }
    }

    "{0,-18} {1,-8} {2,-8} {3,-20} {4}" -f `
        $accountId, $running, $pidText, $lastLogTime, $lastMsg
}

Write-Host "`nLegend:"
Write-Host " RUNNING=YES   -> 策略进程存活"
Write-Host " RUNNING=NO    -> 已退出或异常"
Write-Host " PID=dead      -> 非正常退出（建议 recover）"
