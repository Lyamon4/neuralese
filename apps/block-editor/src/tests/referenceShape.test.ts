import { describe, expect, it } from "vitest";
import { astToTutorialBundle } from "../core/bundleModel";
import { buildBundleFiles } from "../core/bundleExporter";
import type { LessonAst } from "../core/lessonAst";
import { loadTutorialSchema } from "../core/schemaLoader";
import schema from "../schema/tutorialBlocks.schema.json";
import nodeCatalog from "../schema/tutorialNodeCatalog.json";

describe("reference bundle shape", () => {
  it("exports the Neuralese lesson bundle file shape", () => {
    const loaded = loadTutorialSchema(schema, nodeCatalog);
    const ast: LessonAst = {
      bundleName: "Course",
      lessons: [
        {
          key: "intro_lesson",
          title: "Intro lesson",
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
        },
      ],
    };

    const files = buildBundleFiles(astToTutorialBundle(ast, loaded));

    expect(Object.keys(files).sort()).toEqual(["bundle.yaml", "lessons/intro_lesson.yaml"]);
    expect(files["bundle.yaml"]).toContain("lesson_order:");
    expect(files["lessons/intro_lesson.yaml"]).toContain("lesson_title: Intro lesson");
    expect(files["lessons/intro_lesson.yaml"]).toContain("flow:");
    expect(files["lessons/intro_lesson.yaml"]).toContain("step welcome:");
    expect(files["lessons/intro_lesson.yaml"]).toContain("explain:");
    expect(files["lessons/intro_lesson.yaml"]).toContain("branches:");
    expect(files["lessons/intro_lesson.yaml"]).toContain("extra_help:");
  });
});
