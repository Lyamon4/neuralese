#![cfg_attr(all(windows, not(debug_assertions)), windows_subsystem = "windows")]

use serde::{Deserialize, Serialize};
use slint::{ComponentHandle, PhysicalPosition, Timer};
use slint::winit_030::{WinitWindowAccessor, winit};
use std::{
    collections::BTreeSet,
    fs::{self, File},
    io::{self, Cursor, Read, Write},
    path::{Path, PathBuf},
    process::Command,
    sync::{Arc, Mutex},
    time::Duration,
};
use zip::ZipArchive;

#[cfg(windows)]
use std::os::windows::process::CommandExt;
#[cfg(windows)]
use windows_sys::Win32::UI::WindowsAndMessaging::{GetSystemMetrics, SM_CXSCREEN, SM_CYSCREEN};

#[cfg(windows)]
const CREATE_NO_WINDOW: u32 = 0x08000000;

const MARKER_FILE: &str = ".neuralese-install-marker";
const MANIFEST_FILE: &str = ".neuralese-install-manifest.json";
const UNINSTALL_PS1: &str = "uninstall.ps1";
const UNINSTALL_VBS: &str = "uninstall.vbs";

static PAYLOAD_ZIP: &[u8] = include_bytes!("../payload/neuralese_payload.zip");

slint::include_modules!();

fn app_name() -> &'static str {
    option_env!("NEURALESE_APP_NAME").unwrap_or("Neuralese")
}

fn game_exe_name() -> &'static str {
    option_env!("NEURALESE_GAME_EXE").unwrap_or("Neuralese.exe")
}

#[derive(Clone, Debug, Deserialize)]
struct InstallOptions {
    install_dir: String,
    create_desktop_shortcut: bool,
    launch_after_install: bool,
}

#[derive(Clone, Debug)]
struct InstallProgress {
    phase: String,
    percent: f64,
    current_file: String,
}

#[derive(Default, Debug)]
struct ExtractedPayload {
    files: BTreeSet<String>,
    directories: BTreeSet<String>,
}

#[derive(Debug, Serialize)]
struct InstallManifest {
    schema_version: u32,
    app_name: String,
    game_exe_name: String,
    install_root: String,
    marker: String,
    files: Vec<String>,
    directories: Vec<String>,
    shortcuts: Vec<String>,
}

fn default_install_dir() -> Result<String, String> {
    let base_dir =
        default_install_base_dir().ok_or("Could not resolve a default install directory")?;
    Ok(base_dir.join(app_name()).to_string_lossy().to_string())
}

#[cfg(windows)]
fn default_install_base_dir() -> Option<PathBuf> {
    dirs::data_local_dir().map(|path| path.join("Programs"))
}

#[cfg(target_os = "macos")]
fn default_install_base_dir() -> Option<PathBuf> {
    dirs::home_dir().map(|path| path.join("Applications"))
}

#[cfg(all(not(windows), not(target_os = "macos")))]
fn default_install_base_dir() -> Option<PathBuf> {
    dirs::data_local_dir()
        .or_else(dirs::data_dir)
        .or_else(dirs::home_dir)
}

fn fallback_install_dir() -> String {
    let base_dir = dirs::home_dir()
        .or_else(dirs::data_local_dir)
        .unwrap_or_else(std::env::temp_dir);

    base_dir.join(app_name()).to_string_lossy().to_string()
}

fn launch_game(install_dir: String) -> Result<(), String> {
    let install_root = PathBuf::from(install_dir);
    let game_path = find_game_executable(&install_root)?;
    let working_dir = game_path
        .parent()
        .unwrap_or(&install_root)
        .to_path_buf();

    Command::new(&game_path)
        .current_dir(working_dir)
        .spawn()
        .map_err(|err| format!("Failed to launch Neuralese: {err}"))?;

    Ok(())
}

fn install_blocking<F>(options: InstallOptions, emit: F) -> Result<(), String>
where
    F: Fn(InstallProgress),
{
    #[cfg(not(windows))]
    {
        let _ = &options;
        let _ = &emit;
        return Err(
            "This installer currently implements only the Windows install flow. A macOS port needs native app bundle placement, launch, shortcut, and uninstall behavior."
                .to_string(),
        );
    }

    let install_root = PathBuf::from(options.install_dir.trim());

    validate_install_root(&install_root)?;

    emit_progress(&emit, "Preparing install directory", 2.0, install_root.display().to_string());
    fs::create_dir_all(&install_root)
        .map_err(|err| format!("Failed to create install directory: {err}"))?;
    write_install_marker(&install_root)?;

    emit_progress(&emit, "Extracting Neuralese payload", 5.0, "Opening payload archive");
    let extracted = extract_payload(&emit, &install_root)?;

    emit_progress(&emit, "Finishing installation", 90.0, "Validating executable");
    let game_path = find_game_executable(&install_root)?;
    let game_working_dir = game_path
        .parent()
        .unwrap_or(&install_root)
        .to_path_buf();

    let mut shortcuts = Vec::new();

    emit_progress(&emit, "Creating shortcuts", 93.0, "Start Menu");
    shortcuts.push(create_start_menu_shortcut(&game_path, &game_working_dir)?);

    if options.create_desktop_shortcut {
        emit_progress(&emit, "Creating shortcuts", 95.0, "Desktop");
        shortcuts.push(create_desktop_shortcut(&game_path, &game_working_dir)?);
    }

    emit_progress(&emit, "Registering uninstaller", 96.0, "Windows Apps list");
    let (uninstall_ps1, uninstall_vbs) = write_uninstaller_files(&install_root)?;
    shortcuts.push(create_start_menu_uninstall_shortcut(&uninstall_vbs, &install_root, &game_path)?);
    write_install_manifest(&install_root, &extracted, &shortcuts)?;
    register_uninstall_entry(&install_root, &game_path, &uninstall_ps1, &uninstall_vbs)?;

    if options.launch_after_install {
        Command::new(&game_path)
            .current_dir(&game_working_dir)
            .spawn()
            .map_err(|err| format!("Installed, but failed to launch Neuralese: {err}"))?;
    }

    emit_progress(&emit, "Installation complete", 100.0, "Done");
    Ok(())
}

fn validate_install_root(install_root: &Path) -> Result<(), String> {
    if install_root.as_os_str().is_empty() {
        return Err("Install directory is empty".to_string());
    }

    if !install_root.is_absolute() {
        return Err("Install directory must be an absolute path".to_string());
    }

    if is_root_path(install_root) {
        return Err("Refusing to install directly into a drive/root directory".to_string());
    }

    for dangerous in dangerous_user_dirs() {
        if same_path_loose(install_root, &dangerous) {
            return Err(format!(
                "Refusing to install directly into {}. Choose a dedicated Neuralese folder instead.",
                dangerous.display()
            ));
        }
    }

    if install_root.exists() {
        if !install_root.is_dir() {
            return Err("Install path exists but is not a directory".to_string());
        }

        if has_valid_install_marker(install_root) {
            return Ok(());
        }

        if directory_is_empty(install_root)? {
            return Ok(());
        }

        return Err(
            "Selected folder is not empty and is not an existing Neuralese installation. Choose an empty folder or the existing Neuralese folder."
                .to_string(),
        );
    }

    Ok(())
}

fn is_root_path(path: &Path) -> bool {
    path.file_name().is_none() || path.components().count() <= 2
}

fn dangerous_user_dirs() -> Vec<PathBuf> {
    let mut paths = Vec::new();

    if let Some(path) = dirs::home_dir() {
        paths.push(path);
    }
    if let Some(path) = dirs::desktop_dir() {
        paths.push(path);
    }
    if let Some(path) = dirs::document_dir() {
        paths.push(path);
    }
    if let Some(path) = dirs::download_dir() {
        paths.push(path);
    }
    if let Some(path) = dirs::data_dir() {
        paths.push(path);
    }
    if let Some(path) = dirs::data_local_dir() {
        paths.push(path);
    }

    paths
}

fn same_path_loose(a: &Path, b: &Path) -> bool {
    let canonical_a = a.canonicalize().unwrap_or_else(|_| a.to_path_buf());
    let canonical_b = b.canonicalize().unwrap_or_else(|_| b.to_path_buf());

    canonical_a
        .to_string_lossy()
        .trim_end_matches(|ch| ch == '\\' || ch == '/')
        .eq_ignore_ascii_case(canonical_b.to_string_lossy().trim_end_matches(|ch| ch == '\\' || ch == '/'))
}

fn directory_is_empty(path: &Path) -> Result<bool, String> {
    let mut entries = fs::read_dir(path)
        .map_err(|err| format!("Failed to inspect install directory: {err}"))?;
    Ok(entries.next().is_none())
}

fn marker_value() -> String {
    format!("NEURALESE_INSTALL_MARKER_V1:{}", registry_key_name())
}

fn has_valid_install_marker(install_root: &Path) -> bool {
    let path = install_root.join(MARKER_FILE);
    fs::read_to_string(path)
        .map(|content| content.trim() == marker_value())
        .unwrap_or(false)
}

fn write_install_marker(install_root: &Path) -> Result<(), String> {
    fs::write(install_root.join(MARKER_FILE), marker_value())
        .map_err(|err| format!("Failed to write install marker: {err}"))
}

fn extract_payload<F>(emit: &F, install_root: &Path) -> Result<ExtractedPayload, String>
where
    F: Fn(InstallProgress),
{
    let cursor = Cursor::new(PAYLOAD_ZIP);
    let mut archive = ZipArchive::new(cursor).map_err(|err| format!("Invalid payload zip: {err}"))?;
    let total_entries = archive.len().max(1) as f64;
    let mut extracted = ExtractedPayload::default();

    for index in 0..archive.len() {
        let mut entry = archive
            .by_index(index)
            .map_err(|err| format!("Failed to read zip entry {index}: {err}"))?;

        let safe_name = entry
            .enclosed_name()
            .ok_or_else(|| format!("Unsafe zip path rejected: {}", entry.name()))?
            .to_owned();

        let out_path = install_root.join(&safe_name);
        let name_for_ui = safe_name.to_string_lossy().to_string();
        let percent = 5.0 + ((index as f64 / total_entries) * 84.0);

        emit_progress(emit, "Extracting files", percent, &name_for_ui);

        if entry.is_dir() {
            record_directory(&mut extracted, &safe_name);
            fs::create_dir_all(&out_path)
                .map_err(|err| format!("Failed to create directory {}: {err}", out_path.display()))?;
            continue;
        }

        record_file(&mut extracted, &safe_name);

        if let Some(parent) = out_path.parent() {
            fs::create_dir_all(parent)
                .map_err(|err| format!("Failed to create directory {}: {err}", parent.display()))?;
        }

        let mut outfile = File::create(&out_path)
            .map_err(|err| format!("Failed to create file {}: {err}", out_path.display()))?;

        copy_with_small_buffer(&mut entry, &mut outfile)
            .map_err(|err| format!("Failed to extract {}: {err}", out_path.display()))?;
    }

    Ok(extracted)
}

fn record_file(extracted: &mut ExtractedPayload, relative: &Path) {
    extracted.files.insert(manifest_path(relative));

    if let Some(parent) = relative.parent() {
        record_directory(extracted, parent);
    }
}

fn record_directory(extracted: &mut ExtractedPayload, relative: &Path) {
    let mut current = PathBuf::new();

    for component in relative.components() {
        current.push(component.as_os_str());
        let value = manifest_path(&current);
        if !value.is_empty() && value != "." {
            extracted.directories.insert(value);
        }
    }
}

fn manifest_path(path: &Path) -> String {
    path.to_string_lossy().replace('\\', "/")
}

fn copy_with_small_buffer<R: Read, W: Write>(reader: &mut R, writer: &mut W) -> io::Result<u64> {
    let mut buffer = [0_u8; 128 * 1024];
    let mut written = 0;

    loop {
        let len = reader.read(&mut buffer)?;
        if len == 0 {
            break;
        }
        writer.write_all(&buffer[..len])?;
        written += len as u64;
    }

    Ok(written)
}

fn emit_progress<S1: Into<String>, S2: Into<String>, F: Fn(InstallProgress)>(
    emit: &F,
    phase: S1,
    percent: f64,
    current_file: S2,
) {
    emit(InstallProgress {
        phase: phase.into(),
        percent,
        current_file: current_file.into(),
    });
}

fn find_game_executable(install_root: &Path) -> Result<PathBuf, String> {
    let preferred = install_root.join(game_exe_name());
    if preferred.is_file() {
        return Ok(preferred);
    }

    let mut matches = Vec::new();
    find_file_by_name_recursive(install_root, game_exe_name(), &mut matches)
        .map_err(|err| format!("Failed while searching for {}: {err}", game_exe_name()))?;

    if matches.is_empty() {
        return Err(format!(
            "Payload was extracted, but {} was not found. Check -GameExeName or the zip root.",
            game_exe_name()
        ));
    }

    matches.sort();
    Ok(matches.remove(0))
}

fn find_file_by_name_recursive(dir: &Path, file_name: &str, matches: &mut Vec<PathBuf>) -> io::Result<()> {
    for entry in fs::read_dir(dir)? {
        let entry = entry?;
        let path = entry.path();

        if path.is_dir() {
            find_file_by_name_recursive(&path, file_name, matches)?;
        } else if path
            .file_name()
            .and_then(|name| name.to_str())
            .map(|name| name.eq_ignore_ascii_case(file_name))
            .unwrap_or(false)
        {
            matches.push(path);
        }
    }

    Ok(())
}

fn create_desktop_shortcut(target_path: &Path, working_dir: &Path) -> Result<PathBuf, String> {
    let desktop = dirs::desktop_dir().ok_or("Could not resolve Desktop directory")?;
    let shortcut_path = desktop.join(format!("{}.lnk", app_name()));
    create_windows_shortcut(&shortcut_path, target_path, "", working_dir, target_path)?;
    Ok(shortcut_path)
}

fn create_start_menu_shortcut(target_path: &Path, working_dir: &Path) -> Result<PathBuf, String> {
    let start_menu_dir = start_menu_app_dir()?;

    fs::create_dir_all(&start_menu_dir)
        .map_err(|err| format!("Failed to create Start Menu directory: {err}"))?;

    let shortcut_path = start_menu_dir.join(format!("{}.lnk", app_name()));
    create_windows_shortcut(&shortcut_path, target_path, "", working_dir, target_path)?;
    Ok(shortcut_path)
}

fn create_start_menu_uninstall_shortcut(uninstall_vbs: &Path, install_root: &Path, icon_path: &Path) -> Result<PathBuf, String> {
    let start_menu_dir = start_menu_app_dir()?;

    fs::create_dir_all(&start_menu_dir)
        .map_err(|err| format!("Failed to create Start Menu directory: {err}"))?;

    let shortcut_path = start_menu_dir.join(format!("Uninstall {}.lnk", app_name()));
    let args = format!("\"{}\"", uninstall_vbs.display());
    create_windows_shortcut(
        &shortcut_path,
        Path::new("wscript.exe"),
        &args,
        install_root,
        icon_path,
    )?;
    Ok(shortcut_path)
}

fn start_menu_app_dir() -> Result<PathBuf, String> {
    let appdata = std::env::var_os("APPDATA").ok_or("Could not resolve APPDATA directory")?;
    Ok(PathBuf::from(appdata)
        .join("Microsoft")
        .join("Windows")
        .join("Start Menu")
        .join("Programs")
        .join(app_name()))
}

fn create_windows_shortcut(
    shortcut_path: &Path,
    target_path: &Path,
    arguments: &str,
    working_dir: &Path,
    icon_path: &Path,
) -> Result<(), String> {
    let script = format!(
        "$WshShell = New-Object -ComObject WScript.Shell; \
         $Shortcut = $WshShell.CreateShortcut('{}'); \
         $Shortcut.TargetPath = '{}'; \
         $Shortcut.Arguments = '{}'; \
         $Shortcut.WorkingDirectory = '{}'; \
         $Shortcut.IconLocation = '{}'; \
         $Shortcut.Save();",
        ps_quote(shortcut_path),
        ps_quote(target_path),
        ps_quote_str(arguments),
        ps_quote(working_dir),
        ps_quote(icon_path)
    );

    let mut command = Command::new("powershell.exe");
    command.args(["-NoProfile", "-WindowStyle", "Hidden", "-ExecutionPolicy", "Bypass", "-Command", &script]);

    #[cfg(windows)]
    command.creation_flags(CREATE_NO_WINDOW);

    let status = command
        .status()
        .map_err(|err| format!("Failed to start PowerShell for shortcut creation: {err}"))?;

    if !status.success() {
        return Err(format!(
            "PowerShell failed while creating shortcut {}",
            shortcut_path.display()
        ));
    }

    Ok(())
}

fn write_uninstaller_files(install_root: &Path) -> Result<(PathBuf, PathBuf), String> {
    let ps1_path = install_root.join(UNINSTALL_PS1);
    let vbs_path = install_root.join(UNINSTALL_VBS);

    let ps1 = uninstall_ps1_template()
        .replace("__APP_NAME__", &ps_escape_literal(app_name()))
        .replace("__REGISTRY_KEY__", &ps_escape_literal(&registry_key_name()))
        .replace("__MARKER_VALUE__", &ps_escape_literal(&marker_value()))
        .replace("__MANIFEST_FILE__", MANIFEST_FILE)
        .replace("__MARKER_FILE__", MARKER_FILE);

    let vbs = uninstall_vbs_template().replace("__APP_NAME__", &vbs_escape_literal(app_name()));

    fs::write(&ps1_path, ps1)
        .map_err(|err| format!("Failed to write PowerShell uninstaller: {err}"))?;
    fs::write(&vbs_path, vbs)
        .map_err(|err| format!("Failed to write VBS uninstaller launcher: {err}"))?;

    Ok((ps1_path, vbs_path))
}

fn write_install_manifest(
    install_root: &Path,
    extracted: &ExtractedPayload,
    shortcuts: &[PathBuf],
) -> Result<(), String> {
    let mut directories = extracted.directories.iter().cloned().collect::<Vec<_>>();
    directories.sort_by_key(|path| std::cmp::Reverse(path.len()));

    let manifest = InstallManifest {
        schema_version: 1,
        app_name: app_name().to_string(),
        game_exe_name: game_exe_name().to_string(),
        install_root: install_root.to_string_lossy().to_string(),
        marker: marker_value(),
        files: extracted.files.iter().cloned().collect(),
        directories,
        shortcuts: shortcuts
            .iter()
            .map(|path| path.to_string_lossy().to_string())
            .collect(),
    };

    let json = serde_json::to_string_pretty(&manifest)
        .map_err(|err| format!("Failed to serialize install manifest: {err}"))?;

    fs::write(install_root.join(MANIFEST_FILE), json)
        .map_err(|err| format!("Failed to write install manifest: {err}"))
}

fn uninstall_ps1_template() -> &'static str {
    r#"$ErrorActionPreference = 'SilentlyContinue'
$AppName = '__APP_NAME__'
$RegistryKey = '__REGISTRY_KEY__'
$ExpectedMarker = '__MARKER_VALUE__'
$ManifestFile = '__MANIFEST_FILE__'
$MarkerFile = '__MARKER_FILE__'

function Normalize-FullPath([string]$Path) {
    return [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
}

function Test-UnderRoot([string]$Path, [string]$Root) {
    $Full = [System.IO.Path]::GetFullPath($Path)
    $RootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    return $Full.StartsWith($RootFull, [System.StringComparison]::OrdinalIgnoreCase)
}

function Join-Safe([string]$Root, [string]$Relative) {
    if ([System.IO.Path]::IsPathRooted($Relative)) { return $null }
    $Full = [System.IO.Path]::GetFullPath((Join-Path $Root $Relative))
    if (-not (Test-UnderRoot $Full $Root)) { return $null }
    return $Full
}

function Test-AllowedShortcut([string]$ShortcutPath) {
    if ([System.IO.Path]::GetExtension($ShortcutPath) -ne '.lnk') { return $false }

    $Desktop = [Environment]::GetFolderPath('Desktop')
    $StartMenu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'

    return (Test-UnderRoot $ShortcutPath $Desktop) -or (Test-UnderRoot $ShortcutPath $StartMenu)
}

try {
    $InstallRoot = Normalize-FullPath $PSScriptRoot
    $ManifestPath = Join-Path $InstallRoot $ManifestFile
    $MarkerPath = Join-Path $InstallRoot $MarkerFile

    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) { exit 1 }
    if (-not (Test-Path -LiteralPath $MarkerPath -PathType Leaf)) { exit 1 }

    $ActualMarker = (Get-Content -LiteralPath $MarkerPath -Raw).Trim()
    if ($ActualMarker -ne $ExpectedMarker) { exit 1 }

    $Manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
    if ($Manifest.app_name -ne $AppName) { exit 1 }
    if ($Manifest.marker -ne $ExpectedMarker) { exit 1 }

    $ManifestRoot = Normalize-FullPath ([string]$Manifest.install_root)
    if ($ManifestRoot -ne $InstallRoot) { exit 1 }

    foreach ($Shortcut in @($Manifest.shortcuts)) {
        $ShortcutString = [string]$Shortcut
        if ((Test-AllowedShortcut $ShortcutString) -and (Test-Path -LiteralPath $ShortcutString -PathType Leaf)) {
            Remove-Item -LiteralPath $ShortcutString -Force -ErrorAction SilentlyContinue
        }
    }

    foreach ($Relative in @($Manifest.files)) {
        $Target = Join-Safe $InstallRoot ([string]$Relative)
        if ($null -ne $Target -and (Test-Path -LiteralPath $Target -PathType Leaf)) {
            Remove-Item -LiteralPath $Target -Force -ErrorAction SilentlyContinue
        }
    }

    foreach ($Relative in @($Manifest.directories)) {
        $Target = Join-Safe $InstallRoot ([string]$Relative)
        if ($null -ne $Target -and (Test-Path -LiteralPath $Target -PathType Container)) {
            Remove-Item -LiteralPath $Target -Force -ErrorAction SilentlyContinue
        }
    }

    Remove-Item -LiteralPath (Join-Path $InstallRoot 'uninstall.vbs') -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Join-Path $InstallRoot 'uninstall.ps1') -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $MarkerPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $ManifestPath -Force -ErrorAction SilentlyContinue

    $StartMenuDir = Join-Path (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs') $AppName
    Remove-Item -LiteralPath $StartMenuDir -Force -ErrorAction SilentlyContinue

    Remove-Item -LiteralPath "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\$RegistryKey" -Recurse -Force -ErrorAction SilentlyContinue

    Remove-Item -LiteralPath $InstallRoot -Force -ErrorAction SilentlyContinue
} catch {
    exit 1
}
"#
}

fn uninstall_vbs_template() -> &'static str {
    r#"Option Explicit
Dim answer, fso, shell, folder, ps1, command
answer = MsgBox("Uninstall __APP_NAME__?", vbQuestion + vbYesNo, "__APP_NAME__")
If answer <> vbYes Then
    WScript.Quit 0
End If

Set fso = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")
folder = fso.GetParentFolderName(WScript.ScriptFullName)
ps1 = fso.BuildPath(folder, "uninstall.ps1")
command = "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File """ & ps1 & """"
shell.Run command, 0, True
"#
}

#[cfg(windows)]
fn register_uninstall_entry(
    install_root: &Path,
    game_path: &Path,
    uninstall_ps1: &Path,
    uninstall_vbs: &Path,
) -> Result<(), String> {
    use winreg::enums::*;
    use winreg::RegKey;

    let hkcu = RegKey::predef(HKEY_CURRENT_USER);
    let path = format!(
        "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\{}",
        registry_key_name()
    );

    let (key, _) = hkcu
        .create_subkey(path)
        .map_err(|err| format!("Failed to create uninstall registry key: {err}"))?;

    let uninstall_string = format!("wscript.exe \"{}\"", uninstall_vbs.display());
    let quiet_uninstall_string = format!(
        "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File \"{}\"",
        uninstall_ps1.display()
    );

    key.set_value("DisplayName", &app_name())
        .map_err(|err| format!("Failed to write DisplayName: {err}"))?;
    key.set_value("DisplayVersion", &env!("CARGO_PKG_VERSION"))
        .map_err(|err| format!("Failed to write DisplayVersion: {err}"))?;
    key.set_value("Publisher", &"Neuralese")
        .map_err(|err| format!("Failed to write Publisher: {err}"))?;
    key.set_value("InstallLocation", &install_root.to_string_lossy().to_string())
        .map_err(|err| format!("Failed to write InstallLocation: {err}"))?;
    key.set_value("DisplayIcon", &game_path.to_string_lossy().to_string())
        .map_err(|err| format!("Failed to write DisplayIcon: {err}"))?;
    key.set_value("UninstallString", &uninstall_string)
        .map_err(|err| format!("Failed to write UninstallString: {err}"))?;
    key.set_value("QuietUninstallString", &quiet_uninstall_string)
        .map_err(|err| format!("Failed to write QuietUninstallString: {err}"))?;
    key.set_value("NoModify", &1_u32)
        .map_err(|err| format!("Failed to write NoModify: {err}"))?;
    key.set_value("NoRepair", &1_u32)
        .map_err(|err| format!("Failed to write NoRepair: {err}"))?;

    Ok(())
}

#[cfg(not(windows))]
fn register_uninstall_entry(
    _install_root: &Path,
    _game_path: &Path,
    _uninstall_ps1: &Path,
    _uninstall_vbs: &Path,
) -> Result<(), String> {
    Ok(())
}

fn registry_key_name() -> String {
    app_name()
        .chars()
        .filter(|ch| ch.is_ascii_alphanumeric() || *ch == '-' || *ch == '_')
        .collect::<String>()
}

fn ps_quote(path: &Path) -> String {
    ps_quote_str(&path.to_string_lossy())
}

fn ps_quote_str(value: &str) -> String {
    value.replace('\'', "''")
}

fn ps_escape_literal(value: &str) -> String {
    value.replace('\'', "''")
}

fn vbs_escape_literal(value: &str) -> String {
    value.replace('"', "\"\"")
}

fn set_install_progress(ui: &AppWindow, progress: InstallProgress) {
    ui.set_phase(progress.phase.into());
    ui.set_progress(progress.percent as f32);
    ui.set_current_file(progress.current_file.into());
}

fn center_window(ui: &AppWindow) {
    ui.window().with_winit_window(|window| {
        if let Some(monitor) = window.primary_monitor().or_else(|| window.current_monitor()) {
            let monitor_size = monitor.size();
            let monitor_pos = monitor.position();
            let window_size = window.outer_size();
            let x = monitor_pos.x + ((monitor_size.width.saturating_sub(window_size.width)) / 2) as i32;
            let y = monitor_pos.y + ((monitor_size.height.saturating_sub(window_size.height)) / 2) as i32;
            window.set_outer_position(winit::dpi::PhysicalPosition::new(x, y));
        } else {
            let size = ui.window().size();
            ui.window().set_position(PhysicalPosition::new(
                (1920_i32 - size.width as i32) / 2,
                (1080_i32 - size.height as i32) / 2,
            ));
        }
    });
}

#[cfg(windows)]
fn center_window_on_primary_display(ui: &AppWindow) {
    let size = ui.window().size();
    let width = if size.width > 0 { size.width as i32 } else { 520 };
    let height = if size.height > 0 { size.height as i32 } else { 320 };

    unsafe {
        let screen_width = GetSystemMetrics(SM_CXSCREEN);
        let screen_height = GetSystemMetrics(SM_CYSCREEN);
        if screen_width > 0 && screen_height > 0 {
            ui.window().set_position(PhysicalPosition::new(
                ((screen_width - width) / 2).max(0),
                ((screen_height - height) / 2).max(0),
            ));
        }
    }
}

#[cfg(not(windows))]
fn center_window_on_primary_display(_ui: &AppWindow) {}

fn schedule_center_window(ui: &AppWindow, delay_ms: u64) {
    let ui_weak = ui.as_weak();
    Timer::single_shot(Duration::from_millis(delay_ms), move || {
        if let Some(ui) = ui_weak.upgrade() {
            center_window(&ui);
        }
    });
}

fn main() -> Result<(), slint::PlatformError> {
    let ui = AppWindow::new()?;
    let install_dir = default_install_dir().unwrap_or_else(|_| fallback_install_dir());

    ui.set_install_path(install_dir.clone().into());
    ui.set_phase("Preparing".into());
    ui.set_current_file("".into());

    let active_install_dir = Arc::new(Mutex::new(install_dir));

    {
        let ui_weak = ui.as_weak();
        let active_install_dir = Arc::clone(&active_install_dir);
        ui.on_browse_clicked(move || {
            let current = active_install_dir
                .lock()
                .map(|value| value.clone())
                .unwrap_or_default();

            let mut dialog = rfd::FileDialog::new();
            if !current.is_empty() {
                dialog = dialog.set_directory(&current);
            }

            if let Some(folder) = dialog.pick_folder() {
                let selected = folder.to_string_lossy().to_string();
                if let Ok(mut value) = active_install_dir.lock() {
                    *value = selected.clone();
                }
                if let Some(ui) = ui_weak.upgrade() {
                    ui.set_install_path(selected.into());
                }
            }
        });
    }

    {
        let ui_weak = ui.as_weak();
        let active_install_dir = Arc::clone(&active_install_dir);
        ui.on_install_clicked(move || {
            let install_dir = active_install_dir
                .lock()
                .map(|value| value.clone())
                .unwrap_or_default();

            if let Some(ui) = ui_weak.upgrade() {
                ui.set_screen(1);
                ui.set_progress(0.0);
                ui.set_phase("Preparing install directory".into());
                ui.set_current_file(install_dir.clone().into());
            }

            let ui_weak_for_thread = ui_weak.clone();
            std::thread::spawn(move || {
                let options = InstallOptions {
                    install_dir: install_dir.clone(),
                    create_desktop_shortcut: true,
                    launch_after_install: false,
                };

                let result = install_blocking(options, |progress| {
                    let ui_weak = ui_weak_for_thread.clone();
                    let _ = slint::invoke_from_event_loop(move || {
                        if let Some(ui) = ui_weak.upgrade() {
                            set_install_progress(&ui, progress);
                        }
                    });
                });

                let ui_weak = ui_weak_for_thread.clone();
                let _ = slint::invoke_from_event_loop(move || {
                    if let Some(ui) = ui_weak.upgrade() {
                        match result {
                            Ok(()) => {
                                ui.set_progress(100.0);
                                ui.set_phase("Installation complete".into());
                                ui.set_current_file("Done".into());
                                ui.set_screen(2);
                            }
                            Err(err) => {
                                ui.set_error_message(err.into());
                                ui.set_screen(3);
                            }
                        }
                    }
                });
            });
        });
    }

    {
        let ui_weak = ui.as_weak();
        ui.on_retry_clicked(move || {
            if let Some(ui) = ui_weak.upgrade() {
                ui.set_screen(0);
                ui.set_progress(0.0);
                ui.set_phase("Preparing".into());
                ui.set_current_file("".into());
                ui.set_error_message("".into());
            }
        });
    }

    {
        let active_install_dir = Arc::clone(&active_install_dir);
        ui.on_launch_clicked(move || {
            let install_dir = active_install_dir
                .lock()
                .map(|value| value.clone())
                .unwrap_or_default();
            let _ = launch_game(install_dir);
            std::process::exit(0);
        });
    }

    ui.on_finish_clicked(|| {
        std::process::exit(0);
    });

    {
        let ui_weak = ui.as_weak();
        ui.on_minimize_clicked(move || {
            if let Some(ui) = ui_weak.upgrade() {
                ui.window().set_minimized(true);
            }
        });
    }

    ui.on_close_clicked(|| {
        std::process::exit(0);
    });

    {
        let ui_weak = ui.as_weak();
        ui.on_title_pressed(move || {
            if let Some(ui) = ui_weak.upgrade() {
                ui.window().with_winit_window(|window| {
                    let _ = window.drag_window();
                });
            }
        });
    }

    center_window_on_primary_display(&ui);
    ui.show()?;
    center_window(&ui);
    schedule_center_window(&ui, 0);
    schedule_center_window(&ui, 80);
    schedule_center_window(&ui, 240);
    slint::run_event_loop()
}
