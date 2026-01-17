# 当前脚本所在目录（RunScripts）
$SCRIPT_DIR = $PSScriptRoot

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

Write-Host "OK"
Write-Host $CODE_ROOT
