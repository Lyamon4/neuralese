#!/usr/bin/env node
import {
  cpSync,
  existsSync,
  mkdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { createHash } from "node:crypto";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const repoRoot = process.cwd();
const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const templateDir = path.resolve(
  scriptDir,
  "..",
  "syntax-parity",
  "godot-template",
);
const defaultLocalEngine = "D:\\NRLSE\\nnets\\teachneurons";
const monorepoEngine = path.resolve(repoRoot, "..", "builder");
const engineDir = resolveEngineDir();
const outputDir = path.resolve(
  repoRoot,
  process.env.SYNTAX_COMPILER_PROJECT ??
    path.join("generated_syntax_parity", "compiler_project"),
);

assertWithinRepository(outputDir);
assertFile(path.join(templateDir, "project.godot"));

const engineScripts = {
  "dsl_compile.gd": readEngineScript("dsl_compile.gd"),
  "dsl_registry.gd": readEngineScript("dsl_registry.gd"),
  "yaml_comp.gd": readEngineScript("yaml_comp.gd"),
};
const compilerScripts = {
  ...engineScripts,
  "yaml_comp.gd": adaptYamlCompiler(engineScripts["yaml_comp.gd"]),
};

validateCompileBoundary(engineScripts);
const runtimeMethods = referencedCallableMethods(
  engineScripts["dsl_registry.gd"],
  "runtime",
);
if (runtimeMethods.length === 0) {
  fail("dsl_registry.gd exposes no runtime methods; its structure may have changed");
}

rmSync(outputDir, { recursive: true, force: true });
cpSync(templateDir, outputDir, { recursive: true });
mkdirSync(path.join(outputDir, "compiler"), { recursive: true });

for (const [name, source] of Object.entries(compilerScripts)) {
  writeFileSync(path.join(outputDir, "compiler", name), source, "utf8");
}
writeFileSync(
  path.join(outputDir, "compiler", "dsl_runtime.gd"),
  generateRuntimeClone(runtimeMethods),
  "utf8",
);
writeFileSync(
  path.join(outputDir, "compiler", "dsl_graph_utils.gd"),
  generateGraphUtilsClone(),
  "utf8",
);
writeFileSync(
  path.join(outputDir, "compiler", "glob.gd"),
  generateGlobClone(),
  "utf8",
);
writeFileSync(
  path.join(outputDir, "compiler", "registry_access.gd"),
  generateRegistryAccess(),
  "utf8",
);

const yamlAddonSource = path.join(engineDir, "addons", "yaml");
if (!existsSync(yamlAddonSource)) {
  fail(`YAML addon not found: ${yamlAddonSource}`);
}
cpSync(yamlAddonSource, path.join(outputDir, "addons", "yaml"), {
  recursive: true,
});

const sourceManifest = {
  generatedAt: new Date().toISOString(),
  engineDir,
  engineCommit: gitValue(["rev-parse", "HEAD"]),
  engineDirty: gitValue(["status", "--porcelain"]).length > 0,
  copied: Object.fromEntries(
    Object.entries(engineScripts).map(([name, source]) => [
      `scripts/${name}`,
      sha256(source),
    ]),
  ),
  copiedDirectory: "addons/yaml",
  generatedAdapters: {
    yamlZipHelper:
      "glob.unzip_to_temp_dir -> SyntaxParityGlob.unzip_to_temp_dir",
    registry:
      "dsl_reg -> lazily initialized isolated DSLRegistry instance",
    runtime: "generated from dsl_registry.gd runtime.* callable references",
    graphUtils:
      "empty type clone; build fails if dsl_compile.gd invokes graph.*",
  },
  generatedRuntimeMethods: runtimeMethods,
  graphRuntimeCallsInCompiler: [],
};
writeFileSync(
  path.join(outputDir, "source_manifest.json"),
  JSON.stringify(sourceManifest, null, 2),
  "utf8",
);

console.log(
  `Built isolated syntax compiler project at ${path.relative(repoRoot, outputDir)}.`,
);
console.log(
  `Copied compiler commit ${sourceManifest.engineCommit || "unknown"}; generated ${runtimeMethods.length} runtime API stubs.`,
);

function resolveEngineDir() {
  const configured = process.env.NEURALESE_ENGINE_DIR;
  if (configured) return path.resolve(configured);
  if (existsSync(path.join(monorepoEngine, "project.godot"))) {
    return monorepoEngine;
  }
  if (process.platform === "win32" && existsSync(defaultLocalEngine)) {
    return defaultLocalEngine;
  }
  fail(
    "Set NEURALESE_ENGINE_DIR to the current Neuralese Godot repository checkout.",
  );
}

function readEngineScript(name) {
  const sourcePath = path.join(engineDir, "scripts", name);
  assertFile(sourcePath);
  return readFileSync(sourcePath, "utf8");
}

function validateCompileBoundary(sources) {
  const registryCompileMethods = referencedCallableMethods(
    sources["dsl_registry.gd"],
    "compile",
  );
  const implementedCompileMethods = new Set(
    [...sources["dsl_compile.gd"].matchAll(/^func\s+([A-Za-z_]\w*)\s*\(/gm)].map(
      (match) => match[1],
    ),
  );
  const missing = registryCompileMethods.filter(
    (method) => !implementedCompileMethods.has(method),
  );
  if (missing.length > 0) {
    fail(
      `Registry references missing DSLCompile methods: ${missing.join(", ")}`,
    );
  }

  const graphCalls = calledMethods(sources["dsl_compile.gd"], "graph");
  if (graphCalls.length > 0) {
    fail(
      "DSLCompile now invokes graph runtime APIs " +
        `(${graphCalls.join(", ")}). Promote the required implementation into the isolated compiler instead of silently stubbing it.`,
    );
  }
}

function referencedCallableMethods(source, receiver) {
  const pattern = new RegExp(
    `\\b${receiver}\\.([A-Za-z_]\\w*)\\s*,`,
    "g",
  );
  return [
    ...new Set([...source.matchAll(pattern)].map((match) => match[1])),
  ].sort();
}

function calledMethods(source, receiver) {
  const pattern = new RegExp(
    `\\b${receiver}\\.([A-Za-z_]\\w*)\\s*\\(`,
    "g",
  );
  return [
    ...new Set([...source.matchAll(pattern)].map((match) => match[1])),
  ].sort();
}

function generateRuntimeClone(methods) {
  const functions = methods
    .map(
      (method) =>
        `func ${method}(_value = null):\n\treturn null`,
    )
    .join("\n\n");
  return `class_name DSLRuntime
extends RefCounted

# Generated from runtime.* references in the copied dsl_registry.gd.
# YAML compilation stores these Callables but never executes them.

var reg
var graph

${functions}
`;
}

function generateGraphUtilsClone() {
  return `class_name DSLGraphUtils
extends RefCounted

# Generated compile-only type clone. The builder fails if DSLCompile starts
# calling graph runtime methods, preventing a silent reduction in coverage.
`;
}

function generateGlobClone() {
  return `class_name SyntaxParityGlob
extends RefCounted

static func unzip_to_temp_dir(_path: String):
\tpush_error("ZIP inputs are disabled in the isolated syntax compiler")
\treturn null
`;
}

function adaptYamlCompiler(source) {
  const needle = "glob.unzip_to_temp_dir(zip_path)";
  const occurrences = source.split(needle).length - 1;
  if (occurrences !== 1) {
    fail(
      `Expected exactly one '${needle}' call in yaml_comp.gd, found ${occurrences}.`,
    );
  }
  const withZipAdapter = source.replace(
    needle,
    "SyntaxParityGlob.unzip_to_temp_dir(zip_path)",
  );
  const registryReferences = withZipAdapter.match(/\bdsl_reg\b/g)?.length ?? 0;
  if (registryReferences === 0) {
    fail("Expected yaml_comp.gd to reference the dsl_reg compiler registry.");
  }
  return withZipAdapter.replace(
    /\bdsl_reg\b/g,
    "SyntaxParityRegistry.instance()",
  );
}

function generateRegistryAccess() {
  return `class_name SyntaxParityRegistry
extends RefCounted

static var _instance: DSLRegistry

static func instance() -> DSLRegistry:
\tif _instance == null:
\t\t_instance = DSLRegistry.new()
\t\tvar tree := Engine.get_main_loop() as SceneTree
\t\ttree.root.add_child(_instance)
\treturn _instance

static func cleanup() -> void:
\tif _instance == null:
\t\treturn
\t_instance.require.clear()
\t_instance.step_directives.clear()
\t_instance.action.clear()
\t_instance.compile.reg = null
\t_instance.compile.graph = null
\t_instance.runtime.reg = null
\t_instance.runtime.graph = null
\t_instance.compile = null
\t_instance.runtime = null
\t_instance.graph = null
\tvar parent := _instance.get_parent()
\tif parent != null:
\t\tparent.remove_child(_instance)
\t_instance.free()
\t_instance = null
`;
}

function gitValue(args) {
  const result = spawnSync("git", ["-C", engineDir, ...args], {
    encoding: "utf8",
    shell: false,
  });
  return result.status === 0 ? result.stdout.trim() : "";
}

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

function assertFile(filePath) {
  if (!existsSync(filePath)) fail(`Required file not found: ${filePath}`);
}

function assertWithinRepository(target) {
  const relative = path.relative(repoRoot, target);
  if (
    relative === "" ||
    relative.startsWith("..") ||
    path.isAbsolute(relative)
  ) {
    fail(`Generated compiler project must stay inside this repository: ${target}`);
  }
}

function fail(message) {
  console.error(`Syntax compiler build error: ${message}`);
  process.exit(2);
}
