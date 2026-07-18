param(
    [string]$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path,
    [string]$GodotExe = "D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe",
    [string]$Preset = "Windows Desktop",
    [string]$Output = ""
)

$ErrorActionPreference = "Stop"

if (!(Test-Path $GodotExe)) {
    throw "Godot executable not found: $GodotExe"
}

function Get-GodotProcesses([string]$exePath) {
    Get-Process -ErrorAction SilentlyContinue | Where-Object {
        try {
            [string]::Equals($_.Path, $exePath, [System.StringComparison]::OrdinalIgnoreCase)
        }
        catch {
            $false
        }
    }
}

function Wait-NewGodotProcesses([string]$exePath, [int[]]$beforeIds, [datetime]$startedAt) {
    # The Steam Godot tools executable can return control before its worker process
    # has finished first-scan/export work. Wait for newly spawned Godot processes
    # to disappear before continuing to installer packaging.
    $quietRounds = 0
    while ($quietRounds -lt 3) {
        $running = @(
            Get-GodotProcesses $exePath | Where-Object {
                ($beforeIds -notcontains $_.Id) -or ($_.StartTime -ge $startedAt.AddSeconds(-2))
            }
        )

        if ($running.Count -eq 0) {
            $quietRounds += 1
            Start-Sleep -Milliseconds 500
            continue
        }

        $quietRounds = 0
        Start-Sleep -Milliseconds 500
    }
}

$args = @("--headless", "--path", $ProjectRoot, "--export-release", $Preset)
if ($Output.Trim() -ne "") {
    $args += $Output
}

$beforeGodotIds = @(Get-GodotProcesses $GodotExe | Select-Object -ExpandProperty Id)
$startedAt = Get-Date
& $GodotExe @args
$exitCode = $LASTEXITCODE
Wait-NewGodotProcesses $GodotExe $beforeGodotIds $startedAt

if ($exitCode -ne 0) {
    throw "Godot export failed with exit code $exitCode"
}

Write-Host "Neuralese Windows export completed."
