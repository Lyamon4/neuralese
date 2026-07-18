#!/usr/bin/env node
import { existsSync, mkdirSync, writeFileSync } from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const repoRoot = process.cwd();
const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const compilerProject = path.join(
  repoRoot,
  "generated_syntax_parity",
  "compiler_project",
);
const outputDir = path.join(compilerProject, "bin");
const outputPath =
  process.env.SYNTAX_COMPILER_EXE ??
  path.join(outputDir, "neuralese-syntax-compiler.exe");
const tracePath = path.join(
  repoRoot,
  "generated_syntax_parity",
  "godot-export-trace.log",
);
const godotBin = resolveGodotBinary();
const traces = [];

requireSuccess(
  run(process.execPath, [path.join(scriptDir, "build-syntax-compiler.mjs")]),
  "building the isolated compiler project",
);
mkdirSync(outputDir, { recursive: true });
requireSuccess(
  run(godotBin, [
    "--headless",
    "--editor",
    "--path",
    compilerProject,
    "--quit-after",
    "2",
  ]),
  "importing the isolated compiler project",
);
const exportResult = run(godotBin, [
  "--headless",
  "--verbose",
  "--path",
  compilerProject,
  "--export-release",
  "Windows Desktop",
  outputPath,
]);

writeFileSync(tracePath, traces.join("\n\n"), "utf8");
if (!succeeded(exportResult)) {
  console.error(
    "Standalone export failed. Install the export templates matching GODOT_BIN; see godot-export-trace.log.",
  );
  process.exit(exportResult.status ?? 2);
}
console.log(`Standalone syntax compiler: ${path.relative(repoRoot, outputPath)}`);

function run(command, args) {
  const result = spawnSync(command, args, {
    cwd: repoRoot,
    encoding: "utf8",
    shell: false,
    timeout: 180_000,
    maxBuffer: 128 * 1024 * 1024,
  });
  traces.push(
    [
      `command: ${command} ${args.join(" ")}`,
      `status: ${String(result.status)}`,
      "----- stdout -----",
      result.stdout ?? "",
      "----- stderr -----",
      result.stderr ?? "",
    ].join("\n"),
  );
  if (result.stdout) process.stdout.write(result.stdout);
  if (result.stderr) process.stderr.write(result.stderr);
  if (result.error) {
    writeFileSync(tracePath, traces.join("\n\n"), "utf8");
    throw result.error;
  }
  return result;
}

function succeeded(result) {
  return !result.error && result.status === 0;
}

function requireSuccess(result, action) {
  if (succeeded(result)) return;
  writeFileSync(tracePath, traces.join("\n\n"), "utf8");
  console.error(`Standalone export failed while ${action}.`);
  process.exit(result.status ?? 2);
}

function resolveGodotBinary() {
  if (process.env.GODOT_BIN) return process.env.GODOT_BIN;
  const candidates =
    process.platform === "win32"
      ? [
          "D:\\SteamLibrary\\steamapps\\common\\Godot Engine\\godot.windows.opt.tools.64.exe",
          "C:\\Program Files (x86)\\Steam\\steamapps\\common\\Godot Engine\\godot.windows.opt.tools.64.exe",
        ]
      : [];
  return candidates.find(existsSync) ?? "godot";
}
