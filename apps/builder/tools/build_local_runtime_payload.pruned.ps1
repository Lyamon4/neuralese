param(
    [string]$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path,
    [string]$Platform = "windows-x64",
    [switch]$SkipRuntimePrune,
    [switch]$SkipSmokeTest
)

$ErrorActionPreference = "Stop"

$runtimeRoot = Join-Path $ProjectRoot "local_runtime"
$payloadDir = Join-Path $ProjectRoot "runtime_payload"
$buildRoot = Join-Path $ProjectRoot ".runtime_payload_build"
$stageRoot = Join-Path $buildRoot $Platform
$zipPath = Join-Path $payloadDir "$Platform-runtime.zip"
$hashPath = Join-Path $payloadDir "$Platform-runtime.sha256"

function Resolve-FirstExistingPath([string[]]$paths) {
    foreach ($path in $paths) {
        if (Test-Path -LiteralPath $path) {
            return (Resolve-Path -LiteralPath $path).Path
        }
    }
    return ""
}

$pythonExe = Resolve-FirstExistingPath @(
    (Join-Path $runtimeRoot "python\python.exe"),
    (Join-Path $runtimeRoot "python\Scripts\python.exe")
)
if ($pythonExe -eq "") {
    throw "Local runtime Python not found. Checked: local_runtime\python\python.exe and local_runtime\python\Scripts\python.exe"
}

function Copy-Dir([string]$from, [string]$to) {
    if (!(Test-Path -LiteralPath $from)) {
        throw "Required runtime directory missing: $from"
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $to) | Out-Null
    Copy-Item -LiteralPath $from -Destination $to -Recurse -Force
}

function Get-TreeStats([string]$root) {
    if (!(Test-Path -LiteralPath $root)) {
        return [pscustomobject]@{ Files = 0; Dirs = 0; Bytes = 0 }
    }

    $files = @(Get-ChildItem -LiteralPath $root -Recurse -File -Force -ErrorAction SilentlyContinue)
    $dirs = @(Get-ChildItem -LiteralPath $root -Recurse -Directory -Force -ErrorAction SilentlyContinue)
    $bytes = 0L
    foreach ($file in $files) {
        $bytes += [int64]$file.Length
    }
    return [pscustomobject]@{ Files = $files.Count; Dirs = $dirs.Count; Bytes = $bytes }
}

function Format-Bytes([int64]$bytes) {
    if ($bytes -ge 1GB) { return ("{0:N2} GB" -f ($bytes / 1GB)) }
    if ($bytes -ge 1MB) { return ("{0:N2} MB" -f ($bytes / 1MB)) }
    if ($bytes -ge 1KB) { return ("{0:N2} KB" -f ($bytes / 1KB)) }
    return "$bytes B"
}

function Remove-ExistingPath([string]$path) {
    if (Test-Path -LiteralPath $path) {
        Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Remove-ExistingGlob([string]$pattern) {
    Get-ChildItem -Path $pattern -Force -ErrorAction SilentlyContinue | ForEach-Object {
        Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Remove-DirsNamed([string]$root, [string[]]$names) {
    if (!(Test-Path -LiteralPath $root)) { return }
    $nameSet = @{}
    foreach ($name in $names) { $nameSet[$name.ToLowerInvariant()] = $true }

    Get-ChildItem -LiteralPath $root -Recurse -Directory -Force -ErrorAction SilentlyContinue |
        Where-Object { $nameSet.ContainsKey($_.Name.ToLowerInvariant()) } |
        Sort-Object FullName -Descending |
        ForEach-Object {
            Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
        }
}

function Remove-FilesByExtension([string]$root, [string[]]$extensions) {
    if (!(Test-Path -LiteralPath $root)) { return }
    $extSet = @{}
    foreach ($ext in $extensions) { $extSet[$ext.ToLowerInvariant()] = $true }

    Get-ChildItem -LiteralPath $root -Recurse -File -Force -ErrorAction SilentlyContinue |
        Where-Object { $extSet.ContainsKey($_.Extension.ToLowerInvariant()) } |
        ForEach-Object {
            Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
        }
}

function Remove-FilesNamed([string]$root, [string[]]$names) {
    if (!(Test-Path -LiteralPath $root)) { return }
    $nameSet = @{}
    foreach ($name in $names) { $nameSet[$name.ToLowerInvariant()] = $true }

    Get-ChildItem -LiteralPath $root -Recurse -File -Force -ErrorAction SilentlyContinue |
        Where-Object { $nameSet.ContainsKey($_.Name.ToLowerInvariant()) } |
        ForEach-Object {
            Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
        }
}

function Remove-EmptyDirs([string]$root) {
    if (!(Test-Path -LiteralPath $root)) { return }
    do {
        $removed = 0
        Get-ChildItem -LiteralPath $root -Recurse -Directory -Force -ErrorAction SilentlyContinue |
            Sort-Object FullName -Descending |
            ForEach-Object {
                $children = @(Get-ChildItem -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue)
                if ($children.Count -eq 0) {
                    Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
                    $removed += 1
                }
            }
    } while ($removed -gt 0)
}

function Optimize-StageRuntime([string]$stageRoot) {
    $pythonRoot = Join-Path $stageRoot "python"
    $sitePackages = Join-Path $pythonRoot "Lib\site-packages"

    if (!(Test-Path -LiteralPath $sitePackages)) {
        Write-Host "Runtime prune skipped: site-packages not found at $sitePackages"
        return
    }

    Write-Host "Pruning staged Python runtime..."

    # Package managers are useful in the developer runtime, but dead weight in the shipped runtime.
    Remove-ExistingPath (Join-Path $sitePackages "pip")
    Remove-ExistingPath (Join-Path $sitePackages "setuptools")
    Remove-ExistingPath (Join-Path $sitePackages "wheel")
    Remove-ExistingPath (Join-Path $sitePackages "_distutils_hack")
    Remove-ExistingPath (Join-Path $sitePackages "distutils-precedence.pth")
    Remove-ExistingGlob (Join-Path $sitePackages "pip-*.dist-info")
    Remove-ExistingGlob (Join-Path $sitePackages "setuptools-*.dist-info")
    Remove-ExistingGlob (Join-Path $sitePackages "wheel-*.dist-info")
    Remove-ExistingGlob (Join-Path $pythonRoot "Scripts\pip*.exe")
    Remove-ExistingGlob (Join-Path $pythonRoot "Scripts\wheel*.exe")

    # The largest file-count offender in your payload: ONNX backend conformance tests and data.
    Remove-ExistingPath (Join-Path $sitePackages "onnx\backend\test")
    Remove-ExistingPath (Join-Path $sitePackages "onnx\test")

    # NumPy build/test infrastructure. Neuralese uses NumPy at runtime, not as a compiler toolchain.
    Remove-ExistingPath (Join-Path $sitePackages "numpy\distutils")
    Remove-ExistingPath (Join-Path $sitePackages "numpy\f2py")
    Remove-ExistingPath (Join-Path $sitePackages "numpy\_pyinstaller")
    Remove-ExistingPath (Join-Path $sitePackages "numpy\core\include")
    Remove-ExistingPath (Join-Path $sitePackages "numpy\core\lib")
    Remove-ExistingPath (Join-Path $sitePackages "numpy\random\_examples")

    # Test suites and caches across NumPy, SymPy, h5py, mpmath, ONNX Runtime, etc.
    Remove-DirsNamed $sitePackages @("__pycache__", "test", "tests", "testing", "benchmarks")

    # Source/build/type-checking artifacts that are not needed for running Neuralese.
    Remove-FilesByExtension $sitePackages @(
        ".pyi", ".pxd", ".pyx",
        ".h", ".hpp", ".hh",
        ".c", ".cc", ".cpp", ".cxx",
        ".f", ".f90", ".for",
        ".lib", ".a",
        ".pyf"
    )
    Remove-FilesNamed $sitePackages @(
        "setup.py", "setup.cfg", "conftest.py", "meson.build", "meson.build.template",
        "py.typed", "isympy.py",
        "README.md", "README.rst", "API_CHANGES.txt"
    )

    # A wheel file inside installed site-packages is a duplicate payload, not a runtime dependency.
    Remove-ExistingGlob (Join-Path $sitePackages "*.whl")

    # SymPy console docs/manpages are irrelevant in a bundled game/app runtime.
    Remove-ExistingPath (Join-Path $pythonRoot "share")

    Remove-EmptyDirs $pythonRoot
}

function Invoke-RuntimeSmokeTest([string]$stageRoot) {
    $stagePythonExe = Resolve-FirstExistingPath @(
        (Join-Path $stageRoot "python\python.exe"),
        (Join-Path $stageRoot "python\Scripts\python.exe")
    )
    if ($stagePythonExe -eq "") {
        throw "Staged Python executable not found after copy/prune."
    }

    $code = @'
import sys, types
from pathlib import Path
import numpy as np
import onnx
import onnxruntime as ort
import lmdb
training_dir = Path(ort.__file__).resolve().parent / "training"
if training_dir.exists():
    pkg = types.ModuleType("onnxruntime.training")
    pkg.__path__ = [str(training_dir)]
    sys.modules["onnxruntime.training"] = pkg
    from importlib import import_module
    import_module("onnxruntime.training.api")
    import_module("onnxruntime.training.artifacts")
print("runtime smoke ok", np.__version__, onnx.__version__, ort.__version__)
'@

    $oldPythonPath = $env:PYTHONPATH
    if ([string]::IsNullOrWhiteSpace($oldPythonPath)) {
        $env:PYTHONPATH = $stageRoot
    } else {
        $env:PYTHONPATH = "$stageRoot;$oldPythonPath"
    }

    Push-Location $stageRoot
    try {
        & $stagePythonExe -c $code
        if ($LASTEXITCODE -ne 0) {
            throw "Runtime smoke test failed with exit code $LASTEXITCODE."
        }
    } finally {
        Pop-Location
        $env:PYTHONPATH = $oldPythonPath
    }
}

if (Test-Path -LiteralPath $stageRoot) {
    Remove-Item -LiteralPath $stageRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $stageRoot, $payloadDir | Out-Null

Copy-Dir (Join-Path $runtimeRoot "python") (Join-Path $stageRoot "python")
Copy-Dir (Join-Path $runtimeRoot "datasets") (Join-Path $stageRoot "datasets")
Copy-Dir (Join-Path $runtimeRoot "export_cores") (Join-Path $stageRoot "export_cores")

$beforePrune = Get-TreeStats $stageRoot
if (!$SkipRuntimePrune) {
    Optimize-StageRuntime $stageRoot
}
$afterPrune = Get-TreeStats $stageRoot

$compiledSrc = Join-Path $buildRoot "neuralese_local_src"
$compiledOut = Join-Path $stageRoot "neuralese_local"
if (Test-Path -LiteralPath $compiledSrc) {
    Remove-Item -LiteralPath $compiledSrc -Recurse -Force
}
Copy-Dir (Join-Path $runtimeRoot "neuralese_local") $compiledSrc

Get-ChildItem -LiteralPath $compiledSrc -Recurse -Directory -Filter "__pycache__" -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force
& $pythonExe -m compileall -q -b $compiledSrc
if ($LASTEXITCODE -ne 0) {
    throw "Python bytecode compilation failed."
}

New-Item -ItemType Directory -Force -Path $compiledOut | Out-Null
Get-ChildItem -LiteralPath $compiledSrc -Recurse -File -Force | Where-Object {
    $_.Extension -eq ".pyc"
} | ForEach-Object {
    $rel = $_.FullName.Substring($compiledSrc.Length).TrimStart('\', '/')
    $dest = Join-Path $compiledOut $rel
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
    Copy-Item -LiteralPath $_.FullName -Destination $dest -Force
}

if (!$SkipSmokeTest) {
    Invoke-RuntimeSmokeTest $stageRoot
}

$finalStats = Get-TreeStats $stageRoot
$manifest = @{
    platform = $Platform
    built_at = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    contains_source = $false
    python = "python/python.exe"
    pruned = !$SkipRuntimePrune
    files_before_prune = $beforePrune.Files
    files_after_prune = $afterPrune.Files
    files_final = $finalStats.Files
} | ConvertTo-Json -Compress
Set-Content -LiteralPath (Join-Path $stageRoot "runtime_manifest.json") -Value $manifest -Encoding UTF8

if (Test-Path -LiteralPath $zipPath) {
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
Write-Host "  files before prune: $($beforePrune.Files), $((Format-Bytes $beforePrune.Bytes))"
Write-Host "  files after prune:  $($afterPrune.Files), $((Format-Bytes $afterPrune.Bytes))"
Write-Host "  files final:        $($finalStats.Files), $((Format-Bytes $finalStats.Bytes))"
