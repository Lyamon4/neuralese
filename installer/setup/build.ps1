param(
    [Parameter(Mandatory = $true)]
    [string]$PayloadZip,

    [string]$LogoPng = ".\public\logo.png",
    [string]$AppName = "Neuralese",
    [string]$GameExeName = "Neuralese.exe",
    [string]$OutputDir = ".\release"
)

$ErrorActionPreference = "Stop"

function Require-Command($Name, $Hint) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Missing command '$Name'. $Hint"
    }
}

function Sanitize-FileName([string]$Name) {
    return ($Name -replace '[\\/:*?"<>|]', '-')
}

$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

function Join-ProjectPath([string[]]$Parts) {
    $Path = $ProjectRoot
    foreach ($Part in $Parts) {
        $Path = Join-Path $Path $Part
    }
    return $Path
}

$PayloadZip = (Resolve-Path $PayloadZip).Path
$LogoPng = (Resolve-Path $LogoPng).Path
$OutputDirAbs = Join-Path $ProjectRoot $OutputDir

Require-Command "cargo" "Install Rust from https://rustup.rs/."

Write-Host "== Neuralese Setup Bootstrapper Build ==" -ForegroundColor Cyan
Write-Host "Payload: $PayloadZip"
Write-Host "Logo:    $LogoPng"
Write-Host "App:     $AppName"
Write-Host "GameExe: $GameExeName"
Write-Host ""

function Copy-IfDifferent([string]$Source, [string]$Destination) {
    $SourceFull = [System.IO.Path]::GetFullPath($Source)
    $DestinationFull = [System.IO.Path]::GetFullPath($Destination)

    New-Item -ItemType Directory -Path (Split-Path -Parent $DestinationFull) -Force | Out-Null

    if ([string]::Equals($SourceFull, $DestinationFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        Write-Host "Skipping copy; source and destination are the same: $DestinationFull" -ForegroundColor Yellow
        return
    }

    Copy-Item $SourceFull $DestinationFull -Force
}

$PayloadTarget = Join-ProjectPath @("src-tauri", "payload", "neuralese_payload.zip")
$LogoTarget = Join-ProjectPath @("src-tauri", "icons", "icon.png")

Copy-IfDifferent $PayloadZip $PayloadTarget
Copy-IfDifferent $LogoPng $LogoTarget

Push-Location (Join-ProjectPath @("src-tauri"))
try {
    $env:NEURALESE_APP_NAME = $AppName
    $env:NEURALESE_GAME_EXE = $GameExeName

    Write-Host "Building Slint bootstrapper..." -ForegroundColor Cyan
    & cargo build --release
    if ($LASTEXITCODE -ne 0) {
        throw "Cargo build failed with exit code $LASTEXITCODE"
    }

    New-Item -ItemType Directory -Path $OutputDirAbs -Force | Out-Null

    $BuiltExe = Join-ProjectPath @("src-tauri", "target", "release", "neuralese-setup.exe")
    if (-not (Test-Path $BuiltExe)) {
        throw "Build finished, but expected exe was not found: $BuiltExe"
    }

    $FinalName = "$(Sanitize-FileName $AppName)-Setup.exe"
    $FinalPath = Join-Path $OutputDirAbs $FinalName
    Copy-Item $BuiltExe $FinalPath -Force

    Write-Host ""
    Write-Host "Done:" -ForegroundColor Green
    Write-Host $FinalPath -ForegroundColor Green
    Write-Host ""
    Write-Host "Test this setup on a clean Windows VM before shipping." -ForegroundColor Yellow
}
finally {
    Pop-Location
}
