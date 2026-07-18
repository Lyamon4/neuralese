param(
    # This captures the -dev flag directly from the CLI
    [switch]$dev
)

$ErrorActionPreference = "Stop"
$ProjectRoot = "D:\NRLSE\nnets\teachneurons"

if ($dev) {
    Write-Host "Building for dev." -ForegroundColor Cyan
    & "D:\NRLSE\nnets\teachneurons\tools\export_windows_with_runtime.ps1" -ProjectRoot $ProjectRoot -Output "D:\ex\Neuralese.exe"
} else {
    Write-Host "Building for prod." -ForegroundColor Green
    & "D:\NRLSE\nnets\teachneurons\tools\build_pruned.ps1" -ProjectRoot $ProjectRoot -Platform "windows-x64" -SkipSmokeTest -SkipPayloadZip
    & "D:\NRLSE\nnets\teachneurons\tools\export_windows_with_runtime.ps1" -ProjectRoot $ProjectRoot -Output "D:\neuraleseinstaller\game\Neuralese.exe"
    & "D:\NRLSE\nnets\teachneurons\tools\prepare_windows_installer_payload.ps1" -ProjectRoot $ProjectRoot
    & "D:\neuraleseinstaller\build.ps1"
}
