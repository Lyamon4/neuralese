import { describe, expect, it } from "vitest";
import {
  createBlocklyDefinitions,
  recolorBlocklyDropdownArrow,
} from "../blockly/createBlocklyDefinitions";
import { createToolbox } from "../blockly/createToolbox";
import { tutorialBlockStyles } from "../blockly/tutorialTheme";
import { loadTutorialSchema } from "../core/schemaLoader";
import schema from "../schema/tutorialBlocks.schema.json";
import nodeCatalog from "../schema/tutorialNodeCatalog.json";

describe("Blockly schema generation", () => {
  it("creates JSON block definitions from tutorial schema", () => {
    const loaded = loadTutorialSchema(schema, nodeCatalog);
    const defs = createBlocklyDefinitions(loaded);

    expect(defs.some((def) => def.type === "lesson_step")).toBe(true);
    expect(defs.some((def) => def.type === "action_explain")).toBe(true);
  });

  it("adds Blockly connection checks from schema", () => {
    const loaded = loadTutorialSchema(schema, nodeCatalog);
    const defs = createBlocklyDefinitions(loaded);
    const step = defs.find((def) => def.type === "lesson_step");
    const explain = defs.find((def) => def.type === "action_explain");

    expect(step?.nextStatement).toBe("lesson_step");
    expect(JSON.stringify(step?.args0)).toContain("\"check\":\"action\"");
    expect(explain?.previousStatement).toBe("action");
    expect(explain?.nextStatement).toBe("action");
  });

  it("creates a categorized toolbox without hardcoded block ids", () => {
    const loaded = loadTutorialSchema(schema, nodeCatalog);
    const toolbox = createToolbox(loaded);

    expect(toolbox.kind).toBe("categoryToolbox");
    expect(JSON.stringify(toolbox)).toContain("lesson_step");
  });

  it("passes numeric defaults and float constraints to Blockly", () => {
    const loaded = loadTutorialSchema(schema, nodeCatalog);
    const defs = createBlocklyDefinitions(loaded);
    const explain = defs.find((def) => def.type === "action_explain");
    const timeField = (explain?.args0 as Array<Record<string, unknown>>).find(
      (field) => field.name === "time",
    );

    expect(timeField).toMatchObject({
      type: "field_number",
      value: 1,
      min: 0.1,
      precision: 0.1,
    });
  });

  it("supports schema-driven dynamic field visibility", () => {
    const loaded = loadTutorialSchema(schema, nodeCatalog);
    const defs = createBlocklyDefinitions(loaded);
    const explain = defs.find((def) => def.type === "action_explain");
    const timeField = (explain?.args0 as Array<Record<string, unknown>>).find(
      (field) => field.name === "time",
    );
    const timeUnit = (explain?.args0 as Array<Record<string, unknown>>).find(
      (field) => field.name === "time_unit",
    );

    expect(explain?.message0).toBe("Say %1 wait %2 %3 %4");
    expect(explain?.extensions).toContain("tutorial_dynamic_content");
    expect(timeField?.type).toBe("field_number");
    expect(timeUnit).toMatchObject({ type: "field_label", text: "seconds" });
  });

  it("renders schema bool fields with the Neuralese checkbox field", () => {
    const loaded = loadTutorialSchema(schema, nodeCatalog);
    const defs = createBlocklyDefinitions(loaded);
    const step = defs.find((def) => def.type === "lesson_step");
    const persistentField = (step?.args0 as Array<Record<string, unknown>>).find(
      (field) => field.name === "persistent",
    );

    expect(persistentField?.type).toBe("field_neuralese_checkbox");
  });

  it("uses one bright style for every block in the same category", () => {
    const loaded = loadTutorialSchema(schema, nodeCatalog);
    const defs = createBlocklyDefinitions(loaded);
    const root = defs.find((def) => def.type === "lesson_root");
    const step = defs.find((def) => def.type === "lesson_step");
    const explain = defs.find((def) => def.type === "action_explain");
    const ask = defs.find((def) => def.type === "action_ask");

    expect(root?.style).toBe("lesson_hat_blocks");
    expect(step?.style).toBe("lesson_blocks");
    expect(tutorialBlockStyles[root?.style ?? ""]?.colourPrimary).toBe(
      tutorialBlockStyles[step?.style ?? ""]?.colourPrimary,
    );
    expect(explain?.style).toBe("teacher_blocks");
    expect(ask?.style).toBe(explain?.style);
    expect(root?.style).not.toBe(explain?.style);
  });

  it("defines separate hat roots for the main flow and named branches", () => {
    const loaded = loadTutorialSchema(schema, nodeCatalog);
    const defs = createBlocklyDefinitions(loaded);
    const mainRoot = defs.find((def) => def.type === "lesson_root");
    const branchRoot = defs.find((def) => def.type === "lesson_branch");
    const toolbox = createToolbox(loaded);

    expect(mainRoot?.style).toBe("lesson_hat_blocks");
    expect(tutorialBlockStyles[mainRoot?.style ?? ""]?.hat).toBe("cap");
    expect(mainRoot?.previousStatement).toBeUndefined();
    expect(mainRoot?.nextStatement).toBe("lesson_step");
    expect(JSON.stringify(mainRoot?.args0)).not.toContain('"type":"input_statement"');

    expect(branchRoot?.style).toBe("flow_hat_blocks");
    expect(tutorialBlockStyles[branchRoot?.style ?? ""]?.hat).toBe("cap");
    expect(branchRoot?.previousStatement).toBeUndefined();
    expect(branchRoot?.nextStatement).toBe("lesson_step");
    expect(JSON.stringify(branchRoot?.args0)).not.toContain('"type":"input_statement"');
    expect(JSON.stringify(toolbox)).toContain('"type":"lesson_branch"');
  });

  it("renders goto targets as branch-reference dropdowns", () => {
    const loaded = loadTutorialSchema(schema, nodeCatalog);
    const defs = createBlocklyDefinitions(loaded);
    const ask = defs.find((def) => def.type === "action_ask");
    const route = defs.find((def) => def.type === "quiz_answer_route");
    const defaultBranch = (ask?.args0 as Array<Record<string, unknown>>).find(
      (field) => field.name === "default_branch",
    );
    const answerBranch = (route?.args0 as Array<Record<string, unknown>>).find(
      (field) => field.name === "branch",
    );

    expect(defaultBranch).toMatchObject({
      type: "field_neuralese_dropdown",
      options: [["No branch", ""]],
    });
    expect(answerBranch).toMatchObject({
      type: "field_neuralese_dropdown",
      options: [["Create a branch first", ""]],
    });
  });

  it("recolours Blockly's built-in SVG dropdown arrow without replacing its geometry", () => {
    const original =
      "data:image/svg+xml;base64," +
      btoa('<svg><path d="M0 0L6 6L12 0" fill="#fff"/></svg>');
    const recolored = recolorBlocklyDropdownArrow(original, "#1b2631");
    const svg = atob(recolored.split("base64,")[1]);

    expect(svg).toContain('d="M0 0L6 6L12 0"');
    expect(svg).toContain('fill="#1b2631"');
  });

  it("keeps Ask compact with a schema row break and a dedicated option-list editor", () => {
    const loaded = loadTutorialSchema(schema, nodeCatalog);
    const defs = createBlocklyDefinitions(loaded);
    const ask = defs.find((def) => def.type === "action_ask");
    const options = (ask?.args0 as Array<Record<string, unknown>>).find(
      (field) => field.name === "options",
    );

    expect(ask?.message0).toContain(
      "options %2\nCorrect answers %3",
    );
    expect(options?.type).toBe("field_neuralese_option_list");
  });
});
