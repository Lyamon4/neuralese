import { describe, expect, it } from "vitest";
import { loadTutorialSchema } from "../core/schemaLoader";
import { validateLessonAst } from "../core/syntaxGuardrails";
import type { AstBlock, LessonAst } from "../core/lessonAst";
import schema from "../schema/tutorialBlocks.schema.json";
import nodeCatalog from "../schema/tutorialNodeCatalog.json";

describe("syntax guardrails", () => {
  it("accepts a valid lesson AST", () => {
    const loaded = loadTutorialSchema(schema, nodeCatalog);
    const ast: LessonAst = {
      bundleName: "Course",
      lessons: [
        {
          key: "intro",
          title: "Intro",
          blocks: [
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
                          fields: { text: "Hello", wait: "next", time: 1 },
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
        },
      ],
    };

    expect(validateLessonAst(ast, loaded)).toEqual([]);
  });

  it("rejects a lesson without a root block", () => {
    const loaded = loadTutorialSchema(schema, nodeCatalog);
    const ast: LessonAst = {
      bundleName: "Course",
      lessons: [
        {
          key: "intro",
          title: "Intro",
          blocks: [
            {
              type: "action_explain",
              fields: { text: "Orphan", wait: "next" },
              children: [],
              inputs: {},
            },
          ],
        },
      ],
    };

    expect(validateLessonAst(ast, loaded).map((issue) => issue.message)).toContain(
      "Each workspace must contain exactly one main-flow root block.",
    );
  });

  it("rejects more than one lesson root", () => {
    const loaded = loadTutorialSchema(schema, nodeCatalog);
    const root = {
      type: "lesson_root",
      fields: {},
      children: [],
      inputs: { flow: [] },
    };
    const ast: LessonAst = {
      bundleName: "Course",
      lessons: [{ key: "intro", title: "Intro", blocks: [root, root] }],
    };

    expect(validateLessonAst(ast, loaded).map((issue) => issue.message)).toContain(
      "Each workspace must contain exactly one main-flow root block.",
    );
  });

  it("rejects wrong connection types inside action input", () => {
    const loaded = loadTutorialSchema(
      {
        schemaVersion: 1,
        connectionShapes: schema.connectionShapes,
        blocks: [
          ...(schema.blocks as unknown[]),
          {
            type: "fake_topology_edge",
            message: "Topology edge",
            category: "Debug",
            colour: 20,
            kind: "statement",
            fields: [],
            connection: { previous: "topology_edge", next: "topology_edge" },
            emit: { op: "literal", value: {} },
          },
        ],
      },
      nodeCatalog,
    );
    const ast: LessonAst = {
      bundleName: "Course",
      lessons: [
        {
          key: "intro",
          title: "Intro",
          blocks: [
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
                          type: "fake_topology_edge",
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
        },
      ],
    };

    expect(validateLessonAst(ast, loaded).map((issue) => issue.message)).toContain(
      "Only action blocks can be placed inside Actions.",
    );
  });

  it("does not require fields hidden by schema dynamic visibility", () => {
    const loaded = loadTutorialSchema(schema, nodeCatalog);
    const ast: LessonAst = {
      bundleName: "Course",
      lessons: [
        {
          key: "intro",
          title: "Intro",
          blocks: [
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
                          fields: { text: "Hello", wait: "next" },
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
        },
      ],
    };

    expect(validateLessonAst(ast, loaded)).toEqual([]);
  });

  it("requires dynamically visible fields when their condition is active", () => {
    const loaded = loadTutorialSchema(schema, nodeCatalog);
    const ast: LessonAst = {
      bundleName: "Course",
      lessons: [
        {
          key: "intro",
          title: "Intro",
          blocks: [
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
                          fields: { text: "Hello", wait: "time", time: "" },
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
        },
      ],
    };

    expect(validateLessonAst(ast, loaded).map((issue) => issue.message)).toContain(
      "Seconds is required.",
    );
  });

  it("rejects duplicate, reserved, and unknown branch targets", () => {
    const loaded = loadTutorialSchema(schema, nodeCatalog);
    const mainRoot = {
      type: "lesson_root",
      fields: {},
      children: [],
      inputs: {
        flow: [
          {
            type: "lesson_step",
            fields: { id: "question", title: "Question", persistent: "FALSE" },
            children: [],
            inputs: {
              actions: [
                {
                  type: "action_ask",
                  fields: {
                    head: "Choose",
                    options: "One\nTwo",
                    correct: "1",
                    show: "TRUE",
                    default_branch: "missing_branch",
                  },
                  children: [],
                  inputs: {},
                },
              ],
            },
          },
        ],
      },
    };
    const branch = (name: string) => ({
      type: "lesson_branch",
      fields: { name },
      children: [],
      inputs: {
        steps: [
          {
            type: "lesson_step",
            fields: { id: "retry", title: "Retry", persistent: "FALSE" },
            children: [],
            inputs: {
              actions: [
                {
                  type: "action_explain",
                  fields: { text: "Again", wait: "next", time: 1 },
                  children: [],
                  inputs: {},
                },
              ],
            },
          },
        ],
      },
    });
    const ast: LessonAst = {
      bundleName: "Course",
      lessons: [
        {
          key: "intro",
          title: "Intro",
          blocks: [mainRoot, branch("extra_help"), branch("extra_help"), branch("flow")],
        },
      ],
    };

    const messages = validateLessonAst(ast, loaded).map((issue) => issue.message);

    expect(messages).toContain("Branch name 'flow' is reserved.");
    expect(messages).toContain("Branch name 'extra_help' is used more than once.");
    expect(messages).toContain("Goto references unknown branch 'missing_branch'.");
  });

  it("rejects duplicate node creators and references to nodes that are never created", () => {
    const loaded = loadTutorialSchema(schema, nodeCatalog);
    const ast = lessonWithActions([
      nodeCreation("dense"),
      nodeCreation("dense"),
      {
        type: "action_require_node",
        fields: { alias: "missing" },
        children: [],
        inputs: {},
      },
    ]);

    const messages = validateLessonAst(ast, loaded).map((issue) => issue.message);

    expect(messages).toContain(
      "Node 'dense' is created by more than one block.",
    );
    expect(messages).toContain(
      "Node 'missing' is referenced but never created.",
    );
  });

  it("allows a node reference when its creation block appears later", () => {
    const loaded = loadTutorialSchema(schema, nodeCatalog);
    const ast = lessonWithActions([
      {
        type: "action_highlight_bind",
        fields: { alias: "dense" },
        children: [],
        inputs: {},
      },
      nodeCreation("dense"),
    ]);

    expect(validateLessonAst(ast, loaded)).toEqual([]);
  });
});

function nodeCreation(alias: string): AstBlock {
  return {
    type: "action_create_node",
    fields: { node_type: "layer", alias },
    children: [],
    inputs: {},
  };
}

function lessonWithActions(actions: AstBlock[]): LessonAst {
  return {
    bundleName: "Course",
    lessons: [
      {
        key: "intro",
        title: "Intro",
        blocks: [
          {
            type: "lesson_root",
            fields: {},
            children: [],
            inputs: {
              flow: [
                {
                  type: "lesson_step",
                  fields: {
                    id: "step",
                    title: "Step",
                    persistent: "FALSE",
                  },
                  children: [],
                  inputs: { actions },
                },
              ],
            },
          },
        ],
      },
    ],
  };
}
