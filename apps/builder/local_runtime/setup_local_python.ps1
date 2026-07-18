param(
    [string]$Python = "python"
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Venv = Join-Path $Root "python"

$Version = & $Python -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')"
if ($Version -ne "3.11") {
    throw "FullyLocal ORT Training currently needs Python 3.11. Got Python $Version from '$Python'."
}

& $Python -m venv $Venv
& (Join-Path $Venv "Scripts\python.exe") -m pip install --upgrade pip
& (Join-Path $Venv "Scripts\python.exe") -m pip install --no-cache-dir -r (Join-Path $Root "requirements.txt")

Write-Host "FullyLocal Python runtime installed at $Venv"
