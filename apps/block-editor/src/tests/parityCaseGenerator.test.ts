import { describe, expect, it } from "vitest";
import { astToTutorialBundle } from "../core/bundleModel";
import { buildBundleFiles } from "../core/bundleExporter";
import { generateSyntaxParityCases } from "../core/parityCaseGenerator";
import { loadTutorialSchema } from "../core/schemaLoader";
import { validateLessonAst } from "../core/syntaxGuardrails";
import schema from "../schema/tutorialBlocks.schema.json";
import nodeCatalog from "../schema/tutorialNodeCatalog.json";

const loaded = loadTutorialSchema(schema, nodeCatalog);
const cases = generateSyntaxParityCases(loaded);

describe("syntax parity case generator", () => {
  it("covers every schema block without hand-authored block fixtures", () => {
    const covered = new Set(cases.flatMap((testCase) => testCase.coveredBlockTypes));
    expect([...covered].sort()).toEqual(
      [...loaded.blocksByType.keys()].sort(),
    );
  });

  it("covers every select option, boolean value, and compatible statement child", () => {
    const serialized = JSON.stringify(cases.map((testCase) => testCase.ast));

    for (const definition of loaded.blocksByType.values()) {
      for (const field of definition.fields) {
        for (const option of field.options ?? []) {
          expect(serialized).toContain(JSON.stringify(option.value));
        }
        if (field.type === "bool") {
          expect(serialized).toContain(`"${field.name}":"TRUE"`);
          expect(serialized).toContain(`"${field.name}":"FALSE"`);
        }
      }

      for (const input of definition.statementInputs ?? []) {
        const checks = new Set(
          Array.isArray(input.check) ? input.check : [input.check],
        );
        const compatibleTypes = [...loaded.blocksByType.values()]
          .filter((candidate) => {
            const previous = candidate.connection?.previous;
            return previous != null && checks.has(previous);
          })
          .map((candidate) => candidate.type);
        for (const type of compatibleTypes) {
          expect(serialized).toContain(`"type":"${type}"`);
        }
      }
    }
  });

  it("passes every generated case through the production bundle and YAML pipeline", () => {
    for (const testCase of cases) {
      const bundle = astToTutorialBundle(testCase.ast, loaded);
      const files = buildBundleFiles(bundle);
      expect(files["bundle.yaml"]).toContain("lesson_order:");
      expect(files["lessons/generated.yaml"]).toContain("flow:");
    }
  });

  it("passes every generated case through the editor guardrails", () => {
    for (const testCase of cases) {
      expect(
        validateLessonAst(testCase.ast, loaded),
        testCase.id,
      ).toEqual([]);
    }
  });

  it("activates conditional fields while testing their generated values", () => {
    const timedCases = cases.filter((testCase) =>
      testCase.id.startsWith("action_explain_field_time_"),
    );
    const yaml = timedCases.map((testCase) =>
      buildBundleFiles(astToTutorialBundle(testCase.ast, loaded))[
        "lessons/generated.yaml"
      ],
    );
    expect(yaml.some((value) => value.includes("time: 0.1"))).toBe(true);
    expect(yaml.some((value) => value.includes("time: 2.5"))).toBe(true);
    expect(yaml.every((value) => value.includes("wait: time"))).toBe(true);
  });

  it("emits the persistent-step variant through Blockly checkbox values", () => {
    const persistent = cases.find((testCase) => testCase.id === "persistent_step");
    expect(persistent).toBeDefined();
    const yaml = buildBundleFiles(
      astToTutorialBundle(persistent!.ast, loaded),
    )["lessons/generated.yaml"];
    expect(yaml).toContain("persistent: true");
  });
});
