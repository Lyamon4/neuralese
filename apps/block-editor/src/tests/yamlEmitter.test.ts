import { describe, expect, it } from "vitest";
import { loadTutorialSchema } from "../core/schemaLoader";
import { emitWorkspaceBlocksToYamlData } from "../core/yamlEmitter";
import schema from "../schema/tutorialBlocks.schema.json";
import nodeCatalog from "../schema/tutorialNodeCatalog.json";

describe("yamlEmitter", () => {
  it("emits a rooted lesson flow from schema rules", () => {
    const loaded = loadTutorialSchema(schema, nodeCatalog);
    const data = emitWorkspaceBlocksToYamlData(
      [
        {
          type: "lesson_root",
          fields: {},
          children: [],
          inputs: {
            flow: [
              {
                type: "lesson_step",
                fields: { id: "welcome", title: "Welcome", persistent: "FALSE" },
                children: [],
                inputs: {
                  actions: [
                    {
                      type: "action_explain",
                      fields: { text: "Hello", wait: "next", time: 1.5 },
                      children: [],
                      inputs: {},
                    },
                    {
                      type: "action_explain_next",
                      fields: {},
                      children: [],
                      inputs: {},
                    },
                  ],
                },
              },
            ],
          },
        },
      ],
      loaded.emitRulesByType,
    );

    expect(data).toEqual([
      {
        flow: [
          {
            "step welcome": {
              title: "Welcome",
              actions: [
                { explain: { text: ["Hello"], wait: "next" } },
                { explain_next: {} },
              ],
            },
          },
        ],
      },
    ]);
  });

  it("emits each named branch root as a one-key mapping", () => {
    const loaded = loadTutorialSchema(schema, nodeCatalog);
    const data = emitWorkspaceBlocksToYamlData(
      [
        {
          type: "lesson_branch",
          fields: { name: "extra_help" },
          children: [],
          inputs: {
            steps: [
              {
                type: "lesson_step",
                fields: { id: "retry", title: "Try again", persistent: "FALSE" },
                children: [],
                inputs: {
                  actions: [
                    {
                      type: "action_explain",
                      fields: { text: "Look again", wait: "next", time: 1 },
                      children: [],
                      inputs: {},
                    },
                  ],
                },
              },
            ],
          },
        },
      ],
      loaded.emitRulesByType,
    );

    expect(data).toEqual([
      {
        extra_help: [
          {
            "step retry": {
              title: "Try again",
              actions: [{ explain: { text: ["Look again"], wait: "next" } }],
            },
          },
        ],
      },
    ]);
  });

  it("emits ask goto references using exact Neuralese branch syntax", () => {
    const loaded = loadTutorialSchema(schema, nodeCatalog);
    const data = emitWorkspaceBlocksToYamlData(
      [
        {
          type: "action_ask",
          fields: {
            head: "Need help?",
            options: "Yes\nNo",
            correct: "1",
            show: "TRUE",
            default_branch: "extra_help",
          },
          children: [],
          inputs: {
            routes: [
              {
                type: "quiz_answer_route",
                fields: { answer: 1, branch: "extra_help" },
                children: [],
                inputs: {},
              },
            ],
          },
        },
      ],
      loaded.emitRulesByType,
    );

    expect(data).toEqual([
      {
        ask: {
          head: "Need help?",
          options: ["Yes", "No"],
          correct: [1],
          show: true,
          on_answer: {
            "1": { goto: "extra_help" },
          },
          default: { goto: "extra_help" },
        },
      },
    ]);
  });

  it("emits an exact timed explain action with a float duration", () => {
    const loaded = loadTutorialSchema(schema, nodeCatalog);
    const data = emitWorkspaceBlocksToYamlData(
      [
        {
          type: "action_explain",
          fields: { text: "Pause here", wait: "time", time: 2.75 },
          children: [],
          inputs: {},
        },
      ],
      loaded.emitRulesByType,
    );

    expect(data).toEqual([
      { explain: { text: ["Pause here"], wait: "time", time: 2.75 } },
    ]);
  });

  it("does not emit a time property for non-timed explain actions", () => {
    const loaded = loadTutorialSchema(schema, nodeCatalog);
    const data = emitWorkspaceBlocksToYamlData(
      [
        {
          type: "action_explain",
          fields: { text: "Continue", wait: "next", time: 2.75 },
          children: [],
          inputs: {},
        },
      ],
      loaded.emitRulesByType,
    );

    expect(data).toEqual([{ explain: { text: ["Continue"], wait: "next" } }]);
  });

  it("emits valid confetti bodies instead of an empty mapping", () => {
    const loaded = loadTutorialSchema(schema, nodeCatalog);
    const data = emitWorkspaceBlocksToYamlData(
      [
        {
          type: "action_confetti_screen",
          fields: { wait: "FALSE" },
          children: [],
          inputs: {},
        },
        {
          type: "action_confetti_bind",
          fields: { alias: "dense_1" },
          children: [],
          inputs: {},
        },
      ],
      loaded.emitRulesByType,
    );

    expect(data).toEqual([
      { confetti: { whole_screen: true, wait: false } },
      { confetti: { bind: "dense_1" } },
    ]);
  });

  it("emits multi-node create and grouped highlight targets", () => {
    const loaded = loadTutorialSchema(schema, nodeCatalog);
    const data = emitWorkspaceBlocksToYamlData(
      [
        {
          type: "action_create_nodes",
          fields: {},
          children: [],
          inputs: {
            nodes: [
              {
                type: "create_node_entry",
                fields: { alias: "dense", node_type: "layer" },
                children: [],
                inputs: {},
              },
              {
                type: "create_node_entry",
                fields: { alias: "activation", node_type: "neuron" },
                children: [],
                inputs: {},
              },
            ],
          },
        },
        {
          type: "action_highlight_targets",
          fields: {},
          children: [],
          inputs: {
            targets: [
              {
                type: "node_target_bind",
                fields: { alias: "dense" },
                children: [],
                inputs: {},
              },
              {
                type: "node_target_bind",
                fields: { alias: "activation" },
                children: [],
                inputs: {},
              },
            ],
          },
        },
      ],
      loaded.emitRulesByType,
    );

    expect(data).toEqual([
      { create: { dense: "layer", activation: "neuron" } },
      { highlight: { targets: [{ bind: "dense" }, { bind: "activation" }] } },
    ]);
  });
});
