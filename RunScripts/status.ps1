param(
    [Parameter(Mandatory=$true)]
    [string]$KEY_PREFIX,

    # 12-14 / 12,15 / 不传 = 全部
    [string]$ACCOUNTS,

    # 可选：刷新秒数，启用 tail 模式
    [int]$Watch = 0
)

$SCRIPT_DIR = $PSScriptRoot
$CODE_ROOT  = Split-Path $SCRIPT_DIR -Parent
$LOG_DIR    = "$CODE_ROOT\logs"

# 超过多少秒没写 log 认为异常
$LOG_STALE_SECONDS = 120

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

do {

    Clear-Host
    Write-Host "=== StandX STATUS PANEL === $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Cyan
    Write-Host ""

    if ($ACCOUNTS) {
        $ACCOUNT_SET = Parse-Accounts $KEY_PREFIX $ACCOUNTS
    } else {
        $ACCOUNT_SET = Get-ChildItem "$LOG_DIR\$KEY_PREFIX*.log" -ErrorAction SilentlyContinue |
            ForEach-Object {
                [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
            }
    }

    if (-not $ACCOUNT_SET -or $ACCOUNT_SET.Count -eq 0) {
        Write-Host "No accounts found" -ForegroundColor Red
        break
    }

    "{0,-18} {1,-10} {2,-8} {3,-19} {4}" -f `
        "ACCOUNT", "STATUS", "PID", "LAST LOG", "LAST MESSAGE"
    Write-Host ("-" * 90)

    foreach ($accountId in $ACCOUNT_SET) {

        $PID_FILE = "$LOG_DIR\$accountId.pid"
        $LOG_FILE = "$LOG_DIR\$accountId.log"

        $status   = "STOPPED"
        $color    = "DarkGray"
        $pidText  = "-"
        $lastTime = "-"
        $lastMsg  = "-"

        $procPid = $null
        $proc    = $null

        if (Test-Path $PID_FILE) {
            $procPid = Get-Content $PID_FILE -ErrorAction SilentlyContinue
            if ($procPid) {
                $proc = Get-Process -Id $procPid -ErrorAction SilentlyContinue
            }
        }

        if ($proc) {
            $status = "RUNNING"
            $color  = "Green"
            $pidText = $procPid
        }

        if (Test-Path $LOG_FILE) {
            $logItem = Get-Item $LOG_FILE
            $lastTime = $logItem.LastWriteTime.ToString("MM-dd HH:mm:ss")

            $age = (New-TimeSpan $logItem.LastWriteTime (Get-Date)).TotalSeconds
            $lastLine = Get-Content $LOG_FILE -Tail 1 -ErrorAction SilentlyContinue
            if ($lastLine) {
                $lastMsg = $lastLine.Substring(0, [Math]::Min(40, $lastLine.Length))
            }

            if ($proc -and $age -gt $LOG_STALE_SECONDS) {
                $status = "STALLED"
                $color  = "Yellow"
            }
        }

        if ((Test-Path $PID_FILE) -and -not $proc) {
            $status = "ZOMBIE"
            $color  = "Red"
            $pidText = "dead"
        }

        Write-Host (
            "{0,-18} {1,-10} {2,-8} {3,-19} {4}" -f `
            $accountId, $status, $pidText, $lastTime, $lastMsg
        ) -ForegroundColor $color
    }

    if ($Watch -gt 0) {
        Start-Sleep $Watch
    }

} while ($Watch -gt 0)
