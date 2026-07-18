import JSZip from "jszip";
import { describe, expect, it } from "vitest";
import { buildBundleFiles, exportBundleZipBytes } from "../core/bundleExporter";
import type { TutorialBundle } from "../core/bundleModel";

describe("bundleExporter", () => {
  it("writes bundle.yaml and lessons/<key>.yaml", async () => {
    const bundle: TutorialBundle = {
      name: "Teacher Demo",
      lessons: [
        {
          key: "intro",
          title: "Intro lesson",
          flow: [
            {
              "step welcome": {
                title: "Welcome",
                actions: [{ explain: { text: ["Hello"], wait: "next" } }],
              },
            },
          ],
        },
      ],
    };

    const files = buildBundleFiles(bundle);
    expect(files["bundle.yaml"]).toContain("name: Teacher Demo");
    expect(files["lessons/intro.yaml"]).toContain("lesson_title: Intro lesson");

    const zipBytes = await exportBundleZipBytes(bundle);
    const zip = await JSZip.loadAsync(zipBytes);
    expect(zip.file("bundle.yaml")).toBeTruthy();
    expect(zip.file("lessons/intro.yaml")).toBeTruthy();
  });

  it("refuses to export goto targets that do not exist in the lesson", () => {
    const bundle: TutorialBundle = {
      name: "Teacher Demo",
      lessons: [
        {
          key: "intro",
          title: "Intro lesson",
          flow: [
            {
              "step question": {
                title: "Question",
                actions: [
                  {
                    ask: {
                      head: "Choose",
                      options: ["One", "Two"],
                      default: { goto: "missing_branch" },
                    },
                  },
                ],
              },
            },
          ],
        },
      ],
    };

    expect(() => buildBundleFiles(bundle)).toThrow(
      "Goto references unknown branch 'missing_branch'.",
    );
  });
});
