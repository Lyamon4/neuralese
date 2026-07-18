#!/usr/bin/env node
import {
  existsSync,
  readFileSync,
  writeFileSync,
} from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { failureExitCode } from "./syntax-parity-process.mjs";

const repoRoot = process.cwd();
const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const generatedRoot = path.join(repoRoot, "generated_syntax_parity");
const compilerProject = path.join(generatedRoot, "compiler_project");
const reportPath = path.join(generatedRoot, "godot_compile_report.json");
const engineLogPath = path.join(generatedRoot, "godot-engine.log");
const importLogPath = path.join(generatedRoot, "godot-import.log");
const processTracePath = path.join(generatedRoot, "godot-process-trace.log");
const godotBin = resolveGodotBinary();
const traceSections = [];

runRequired(
  process.execPath,
  [
    path.join(repoRoot, "node_modules", "tsx", "dist", "cli.mjs"),
    path.join(scriptDir, "generate-syntax-parity-inputs.ts"),
  ],
  "generate YAML cases",
);
runRequired(
  process.execPath,
  [path.join(scriptDir, "build-syntax-compiler.mjs")],
  "build isolated Godot compiler",
);

console.log(`Godot binary: ${godotBin}`);
const importResult = runCaptured(
  godotBin,
  [
    "--headless",
    "--editor",
    "--verbose",
    "--path",
    compilerProject,
    "--log-file",
    importLogPath,
    "--quit-after",
    "2",
  ],
  "import isolated Godot compiler project",
);

if (!succeeded(importResult)) {
  finishTrace();
  printResult(importResult);
  failWithResult(
    "Godot could not import the isolated compiler project",
    importResult,
  );
}

const compileResult = runCaptured(
  godotBin,
  [
    "--headless",
    "--verbose",
    "--path",
    compilerProject,
    "--log-file",
    engineLogPath,
    "--",
    `--input=${generatedRoot}`,
    `--report=${reportPath}`,
  ],
  "compile generated YAML cases",
);

finishTrace();
printResult(compileResult);

if (!existsSync(reportPath)) {
  failWithResult(
    `Godot did not produce ${path.relative(repoRoot, reportPath)}`,
    compileResult,
  );
}

const report = JSON.parse(readFileSync(reportPath, "utf8"));
console.log(
  `Syntax parity: ${report.passed}/${report.total} generated cases passed.`,
);
console.log(`Case report: ${path.relative(repoRoot, reportPath)}`);
console.log(`Full engine log: ${path.relative(repoRoot, engineLogPath)}`);
console.log(`Full process trace: ${path.relative(repoRoot, processTracePath)}`);

if (!succeeded(compileResult) || !report.ok) {
  process.exit(1);
}

function runRequired(command, args, label) {
  const result = spawnSync(command, args, {
    cwd: repoRoot,
    encoding: "utf8",
    shell: false,
    timeout: 120_000,
    maxBuffer: 128 * 1024 * 1024,
  });
  traceSections.push(formatTraceSection(label, command, args, result));
  printResult(result);
  if (!succeeded(result)) {
    finishTrace();
    failWithResult(`Failed to ${label}`, result);
  }
}

function runCaptured(command, args, label) {
  const result = spawnSync(command, args, {
    cwd: repoRoot,
    encoding: "utf8",
    shell: false,
    timeout: 120_000,
    maxBuffer: 128 * 1024 * 1024,
  });
  traceSections.push(formatTraceSection(label, command, args, result));
  return result;
}

function formatTraceSection(label, command, args, result) {
  return [
    `===== ${label} =====`,
    `command: ${quote(command)} ${args.map(quote).join(" ")}`,
    `status: ${String(result.status)}`,
    `signal: ${String(result.signal)}`,
    `error: ${result.error?.stack ?? ""}`,
    "----- stdout -----",
    result.stdout ?? "",
    "----- stderr -----",
    result.stderr ?? "",
    "",
  ].join("\n");
}

function finishTrace() {
  writeFileSync(processTracePath, traceSections.join("\n"), "utf8");
}

function printResult(result) {
  if (result.stdout) process.stdout.write(result.stdout);
  if (result.stderr) process.stderr.write(result.stderr);
}

function succeeded(result) {
  return !result.error && result.status === 0;
}

function failWithResult(message, result) {
  if (result.error?.code === "ENOENT") {
    console.error(
      `Syntax parity setup error: Could not launch Godot. Set GODOT_BIN to the Godot executable.`,
    );
  } else if (result.error?.code === "ETIMEDOUT") {
    console.error(`Syntax parity setup error: ${message}: process timed out.`);
  } else {
    console.error(`Syntax parity setup error: ${message}.`);
  }
  process.exit(failureExitCode(result));
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

function quote(value) {
  const text = String(value);
  return /\s/.test(text) ? JSON.stringify(text) : text;
}
