#!/usr/bin/env node
import { mkdir, rm, writeFile } from "node:fs/promises";
import path from "node:path";
import { astToTutorialBundle } from "../src/core/bundleModel";
import { buildBundleFiles } from "../src/core/bundleExporter";
import { generateSyntaxParityCases } from "../src/core/parityCaseGenerator";
import { loadTutorialSchema } from "../src/core/schemaLoader";
import schema from "../src/schema/tutorialBlocks.schema.json";
import nodeCatalog from "../src/schema/tutorialNodeCatalog.json";

const repoRoot = process.cwd();
const outputRoot = path.resolve(
  repoRoot,
  process.env.SYNTAX_PARITY_OUTPUT ?? "generated_syntax_parity",
);

if (!isWithin(repoRoot, outputRoot)) {
  throw new Error(`Parity output must stay inside the repository: ${outputRoot}`);
}

const loaded = loadTutorialSchema(schema, nodeCatalog);
const cases = generateSyntaxParityCases(loaded);

await rm(outputRoot, { recursive: true, force: true });
await mkdir(outputRoot, { recursive: true });

for (const testCase of cases) {
  const bundle = astToTutorialBundle(testCase.ast, loaded);
  const files = buildBundleFiles(bundle);
  const caseRoot = path.join(outputRoot, testCase.id);
  for (const [relativePath, contents] of Object.entries(files)) {
    const target = path.join(caseRoot, relativePath);
    await mkdir(path.dirname(target), { recursive: true });
    await writeFile(target, contents, "utf8");
  }
}

await writeFile(
  path.join(outputRoot, "manifest.json"),
  JSON.stringify(
    {
      schemaVersion: schema.schemaVersion,
      generatedAt: new Date().toISOString(),
      caseCount: cases.length,
      cases: cases.map(({ id, description, coveredBlockTypes }) => ({
        id,
        description,
        coveredBlockTypes,
      })),
    },
    null,
    2,
  ),
  "utf8",
);

console.log(
  `Generated ${cases.length} syntax-parity bundles in ${path.relative(repoRoot, outputRoot)}.`,
);

function isWithin(parent: string, child: string): boolean {
  const relative = path.relative(parent, child);
  return relative !== "" && !relative.startsWith("..") && !path.isAbsolute(relative);
}
