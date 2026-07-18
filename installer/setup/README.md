# Neuralese Setup Bootstrapper

This repository currently builds a custom Windows setup bootstrapper for a
Neuralese/Godot payload zip. The active installer app is Rust + Slint, not the
Vite/Tauri web frontend that is still present in the repository.

The current shippable installer is Windows-only. The UI, zip extraction, path
validation, and manifest-writing logic are reusable, but shortcuts, uninstall
registration, launch behavior, payload naming, and release packaging all need
native macOS work before this can become a Mac installer.

## Current Status

- Active app entrypoint: `src-tauri/src/main.rs`
- Active UI definition: `src-tauri/ui/app.slint`
- Build script: `build.ps1`
- Compatibility build script: `build-installer.ps1`
- Embedded payload at build time: `src-tauri/payload/neuralese_payload.zip`
- Windows output: `release/<AppName>-Setup.exe`

The `src/`, `index.html`, `package.json`, and `vite.config.ts` files are from a
Tauri/Vite path. They are not used by the current `build.ps1` flow because the
Rust app does not depend on the `tauri` crate and uses Slint directly.

## Repository Layout

```text
.
  build.ps1                  Windows release build script
  build-installer.ps1        Compatibility copy of the build script
  public/                    Web frontend assets, currently inactive
  src/                       Web frontend code, currently inactive
  src-tauri/
    src/main.rs              Active installer runtime
    ui/app.slint             Active installer UI
    payload/                 Build script stages the payload zip here
    icons/                   App icons
    fonts/                   Slint UI fonts
    Cargo.toml               Rust crate manifest
```

Generated build artifacts are ignored by Git: `node_modules/`, `dist/`,
`src-tauri/target/`, `release/`, `src-tauri/gen/schemas/`, and staged payload
zips under `src-tauri/payload/`.

## Requirements

For the current Windows bootstrapper:

- Windows 10 or Windows 11
- Rust toolchain from `https://rustup.rs/`
- Microsoft C++ Build Tools or Visual Studio Build Tools
- PowerShell

Node.js is only needed if you intentionally work on the inactive Vite/Tauri
frontend. The current Slint build path does not run `npm install` or
`npm run build`.

## Build On Windows

From the repository root:

```powershell
.\build.ps1 `
  -PayloadZip ".\payloads\neuralese_payload.zip" `
  -LogoPng ".\public\logo.png" `
  -AppName "Neuralese" `
  -GameExeName "Neuralese.exe"
```

Output:

```text
release\Neuralese-Setup.exe
```

`build-installer.ps1` has the same behavior and is kept for compatibility.

The build script derives paths from its own location, so the checkout can live
anywhere on disk. It copies:

- The payload zip to `src-tauri/payload/neuralese_payload.zip`
- The selected logo to `src-tauri/icons/icon.png`

Then it runs:

```powershell
cargo build --release
```

inside `src-tauri/`, and copies the built binary from
`src-tauri/target/release/neuralese-setup.exe` into `release/`.

## Payload Zip

The payload zip is embedded into the installer binary at compile time with
`include_bytes!`. Do not run `cargo build` directly unless
`src-tauri/payload/neuralese_payload.zip` already exists. The build scripts
stage that file for you.

Preferred payload layout:

```text
neuralese_payload.zip
  Neuralese.exe
  Neuralese.pck
  addons/
  other-runtime-files/
```

Nested payloads are supported by the current installer because it searches
recursively for `-GameExeName` after extraction, but root-level payloads are
cleaner and easier to validate.

## Build Options

`build.ps1` accepts:

- `-PayloadZip`: Required. Path to the payload zip to embed.
- `-LogoPng`: Optional. Defaults to `.\public\logo.png`.
- `-AppName`: Optional. Defaults to `Neuralese`.
- `-GameExeName`: Optional. Defaults to `Neuralese.exe`.
- `-OutputDir`: Optional. Defaults to `.\release`.

`-AppName` and `-GameExeName` are passed to Rust as compile-time environment
variables:

```text
NEURALESE_APP_NAME
NEURALESE_GAME_EXE
```

## Runtime Behavior On Windows

The installer:

1. Defaults the install path to `%LOCALAPPDATA%\Programs\<AppName>`.
2. Lets the user browse for a different install directory.
3. Rejects empty paths, drive roots, common user directories, non-empty
   unrelated folders, and unsafe zip entries.
4. Writes `.neuralese-install-marker`.
5. Extracts the embedded payload zip.
6. Finds `-GameExeName`, including nested matches.
7. Creates Start Menu and Desktop shortcuts.
8. Writes uninstall helper files into the install directory.
9. Writes `.neuralese-install-manifest.json`.
10. Registers the app under the current user's Windows uninstall registry key.

## Relative Path Cleanup

There should be no machine-specific checkout paths in the repo.

Current path behavior:

- Build scripts resolve paths relative to the script directory.
- The Rust fallback install directory uses the user's home directory or temp
  directory instead of a hardcoded drive root.
- README examples use relative placeholder paths.

Useful audit command:

```powershell
rg -n "[A-Za-z]:\\|D:\\|C:\\" -S -g "!node_modules/**" -g "!src-tauri/target/**" -g "!dist/**" -g "!release/**"
```

Some Windows strings will still appear intentionally, such as registry paths,
PowerShell commands, `.exe`, `.lnk`, and Windows API names.

## Windows Dependency Analysis

The current installer is Windows-dependent for shipping purposes.

Portable or mostly portable pieces:

- Slint UI layout in `src-tauri/ui/app.slint`
- Zip validation and extraction
- Install marker and manifest file format
- Recursive payload executable search
- Basic path validation logic

Windows-specific pieces:

- `src-tauri/src/main.rs`
  - Default install target is `%LOCALAPPDATA%\Programs\<AppName>` on Windows.
  - Desktop and Start Menu shortcuts are `.lnk` files.
  - Shortcut creation shells out to `powershell.exe` and `WScript.Shell`.
  - Uninstall launch uses `uninstall.vbs` and `uninstall.ps1`.
  - Windows Apps list registration uses `HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall`.
  - `winreg` writes the uninstall registry entry.
  - `windows-sys` calls `GetSystemMetrics` for primary-display centering.
  - Release builds use `windows_subsystem = "windows"` to hide the console.
- `src-tauri/build.rs`
  - On Windows, `winresource` embeds `app.manifest`, icon resources, product
    name, file description, and company name.
- `build.ps1` and `build-installer.ps1`
  - They produce a Windows `.exe` bootstrapper.

The Rust installer now fails early on non-Windows if the user clicks Install,
before extracting files. This is intentional so a Mac test run does not create a
partial install and then fail later in Windows shortcut or registry code.

## macOS Port Notes

The Mac port should not be a direct translation of Windows installer behavior.
Treat it as a platform-specific install flow that can reuse shared extraction,
validation, manifest, and UI concepts.

Recommended decisions:

1. Decide whether Neuralese ships as a Godot `.app` bundle, a zip containing a
   `.app`, a `.dmg`, or a signed `.pkg`.
2. Prefer installing to `~/Applications/<AppName>.app` for a user-level
   installer, or `/Applications/<AppName>.app` for a system-level installer
   with privilege handling.
3. Replace `GameExeName = Neuralese.exe` with Mac bundle or executable
   discovery, such as `Neuralese.app` or `Neuralese.app/Contents/MacOS/<name>`.
4. Replace Windows shortcut creation with macOS-native placement in
   Applications, LaunchServices registration if needed, and optional Dock
   guidance.
5. Replace registry uninstall with either a manifest-driven remover, a pkg
   receipt-based uninstall path, or standard app bundle removal.
6. Replace `wscript.exe`, PowerShell uninstall scripts, `.lnk` files, and HKCU
   registry logic with macOS equivalents.
7. Add code signing, notarization, and stapling to the release process before
   shipping outside development machines.
8. Revisit window behavior on macOS. Frameless transparent windows and custom
   drag regions may behave differently across display scale factors and macOS
   versions.

Suggested implementation shape:

- Split platform install integration into Windows and macOS modules.
- Keep payload extraction and manifest writing platform-neutral.
- Add a macOS-specific payload validator that understands `.app` bundles.
- Add a macOS release script, for example `build-macos.ps1` or `build-macos.sh`.
- Keep the Windows bootstrapper build scripts unchanged except for shared
  helpers.

## Verification

After changing installer code:

```powershell
cargo check --manifest-path .\src-tauri\Cargo.toml
```

For a release smoke test:

```powershell
.\build.ps1 -PayloadZip ".\payloads\neuralese_payload.zip"
.\release\Neuralese-Setup.exe
```

Test the final installer on a clean Windows VM before shipping.

## Troubleshooting

If `cargo build` fails with a missing payload file, run `build.ps1` with
`-PayloadZip` instead of invoking Cargo directly.

If the installed app cannot launch, verify that `-GameExeName` matches the
actual executable in the zip. Nested executables are supported, but root-level
payloads are preferred.

If shortcuts or uninstall registration fail, test on a normal non-admin user
account first. The installer is designed for per-user installation and writes to
HKCU, not HKLM.
