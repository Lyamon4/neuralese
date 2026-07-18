import { describe, expect, it } from "vitest";
import { loadTutorialSchema } from "../core/schemaLoader";
import schema from "../schema/tutorialBlocks.schema.json";
import nodeCatalog from "../schema/tutorialNodeCatalog.json";

describe("loadTutorialSchema", () => {
  it("loads block definitions and emit rules from JSON", () => {
    const loaded = loadTutorialSchema(schema, nodeCatalog);

    expect(loaded.blocksByType.has("lesson_step")).toBe(true);
    expect(loaded.emitRulesByType.has("lesson_step")).toBe(true);
    expect(loaded.connectionShapes.has("lesson_step")).toBe(true);
    expect(loaded.connectionShapes.has("action")).toBe(true);
    expect(loaded.toolboxCategories.length).toBeGreaterThan(0);
  });

  it("hydrates node_type dropdown options with DSL node ids", () => {
    const loaded = loadTutorialSchema(schema, nodeCatalog);
    const createNode = loaded.blocksByType.get("action_create_node");
    const nodeField = createNode?.fields.find((field) => field.name === "node_type");

    expect(nodeField?.options?.some((option) => option.value === "layer")).toBe(true);
    expect(nodeField?.options?.some((option) => option.value === "ПлотнСлой")).toBe(false);
  });
});
