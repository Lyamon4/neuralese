param(
    [string]$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path,
    [string]$GameDir = "D:\neuraleseinstaller\game",
    [string]$OutputZip = "D:\neuraleseinstaller\game.zip",
    [string]$Platform = "windows-x64"
)

$ErrorActionPreference = "Stop"

$stageRoot = Join-Path $ProjectRoot ".runtime_payload_build\$Platform"
$manifestPath = Join-Path $stageRoot "runtime_manifest.json"

if (!(Test-Path -LiteralPath $manifestPath)) {
    throw "Runtime stage manifest missing: $manifestPath. Run tools\build_pruned.ps1 -SkipPayloadZip before preparing the installer payload."
}
if (!(Test-Path -LiteralPath $GameDir)) {
    throw "Game directory missing: $GameDir"
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if ($manifest.pruned -ne $true) {
    throw "Installer payload requires a pruned runtime stage."
}
if ([int]$manifest.files_final -gt 5000) {
    throw "Runtime stage looks unpruned ($($manifest.files_final) files)."
}

$gameExe = Join-Path $GameDir "Neuralese.exe"
if (!(Test-Path -LiteralPath $gameExe)) {
    throw "Game executable missing: $gameExe"
}

$destRoot = Join-Path $GameDir "local_runtime\$Platform"
if (Test-Path -LiteralPath $destRoot) {
    Remove-Item -LiteralPath $destRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $destRoot | Out-Null

Copy-Item -Path (Join-Path $stageRoot "*") -Destination $destRoot -Recurse -Force

$installedManifest = @{
    platform = $Platform
    installed_at = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    pruned = $true
    source_fingerprint = [string]$manifest.source_fingerprint
    source = "installer_payload"
} | ConvertTo-Json -Compress
Set-Content -LiteralPath (Join-Path $destRoot ".neuralese_runtime_manifest.json") -Value $installedManifest -Encoding UTF8

$pythonExe = Join-Path $destRoot "python\python.exe"
if (!(Test-Path -LiteralPath $pythonExe)) {
    throw "Prepared installer runtime has no Python executable: $pythonExe"
}

if (Test-Path -LiteralPath $OutputZip) {
    Remove-Item -LiteralPath $OutputZip -Force
}

$items = Get-ChildItem -LiteralPath $GameDir | Select-Object -ExpandProperty FullName
Compress-Archive -Path $items -DestinationPath $OutputZip -CompressionLevel Optimal

Write-Host "Prepared Neuralese installer game payload:"
Write-Host "  game dir:  $GameDir"
Write-Host "  output:    $OutputZip"
Write-Host "  runtime:   $destRoot"
Write-Host "  source_fingerprint: $($manifest.source_fingerprint)"
Write-Host "  files:     $($manifest.files_final)"
Write-Host ""
Write-Host "Important: export Neuralese.exe with tools\export_windows_with_runtime.ps1 before this step so the installer payload contains the current executable."
