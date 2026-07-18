param(
    [string]$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path,
    [string]$Platform = "windows-x64"
)

$ErrorActionPreference = "Stop"

$runtimeRoot = Join-Path $ProjectRoot "local_runtime"
$pythonExe = Join-Path $runtimeRoot "python\python.exe"
$payloadDir = Join-Path $ProjectRoot "runtime_payload"
$buildRoot = Join-Path $ProjectRoot ".runtime_payload_build"
$stageRoot = Join-Path $buildRoot $Platform
$zipPath = Join-Path $payloadDir "$Platform-runtime.zip"
$hashPath = Join-Path $payloadDir "$Platform-runtime.sha256"

if (!(Test-Path $pythonExe)) {
    throw "Local runtime Python not found: $pythonExe"
}

if (Test-Path $stageRoot) {
    Remove-Item -LiteralPath $stageRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $stageRoot, $payloadDir | Out-Null

function Copy-Dir($from, $to) {
    if (!(Test-Path $from)) {
        throw "Required runtime directory missing: $from"
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $to) | Out-Null
    Copy-Item -LiteralPath $from -Destination $to -Recurse -Force
}

Copy-Dir (Join-Path $runtimeRoot "python") (Join-Path $stageRoot "python")
Copy-Dir (Join-Path $runtimeRoot "datasets") (Join-Path $stageRoot "datasets")
Copy-Dir (Join-Path $runtimeRoot "export_cores") (Join-Path $stageRoot "export_cores")

$compiledSrc = Join-Path $buildRoot "neuralese_local_src"
$compiledOut = Join-Path $stageRoot "neuralese_local"
if (Test-Path $compiledSrc) {
    Remove-Item -LiteralPath $compiledSrc -Recurse -Force
}
Copy-Dir (Join-Path $runtimeRoot "neuralese_local") $compiledSrc

Get-ChildItem -LiteralPath $compiledSrc -Recurse -Directory -Filter "__pycache__" | Remove-Item -Recurse -Force
& $pythonExe -m compileall -q -b $compiledSrc
if ($LASTEXITCODE -ne 0) {
    throw "Python bytecode compilation failed."
}

New-Item -ItemType Directory -Force -Path $compiledOut | Out-Null
Get-ChildItem -LiteralPath $compiledSrc -Recurse -File | Where-Object {
    $_.Extension -eq ".pyc"
} | ForEach-Object {
    $rel = $_.FullName.Substring($compiledSrc.Length).TrimStart('\', '/')
    $dest = Join-Path $compiledOut $rel
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
    Copy-Item -LiteralPath $_.FullName -Destination $dest -Force
}

$manifest = @{
    platform = $Platform
    built_at = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    contains_source = $false
    python = "python/python.exe"
} | ConvertTo-Json -Compress
Set-Content -LiteralPath (Join-Path $stageRoot "runtime_manifest.json") -Value $manifest -Encoding UTF8

if (Test-Path $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}
$stageItems = Get-ChildItem -LiteralPath $stageRoot | Select-Object -ExpandProperty FullName
Compress-Archive -Path $stageItems -DestinationPath $zipPath -CompressionLevel Optimal

$hash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
Set-Content -LiteralPath $hashPath -Value "$hash  $Platform-runtime.zip" -Encoding ASCII

Write-Host "Built local runtime payload:"
Write-Host "  $zipPath"
Write-Host "  $hashPath"
Write-Host "  sha256=$hash"
