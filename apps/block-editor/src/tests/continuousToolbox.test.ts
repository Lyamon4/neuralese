import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";
import { createToolbox } from "../blockly/createToolbox";
import { loadTutorialSchema } from "../core/schemaLoader";
import schema from "../schema/tutorialBlocks.schema.json";
import nodeCatalog from "../schema/tutorialNodeCatalog.json";

const loaded = loadTutorialSchema(schema, nodeCatalog);

type ToolboxCategory = {
  kind: "category";
  name: string;
  colour?: string | number;
  contents: Array<{ kind: string; type: string }>;
};

describe("continuous Blockly toolbox", () => {
  it("keeps schema category order and derives every marker colour from its blocks", () => {
    const toolbox = createToolbox(loaded);
    const categories = toolbox.contents.filter(
      (item) => item.kind === "category",
    ) as ToolboxCategory[];
    const expected = loaded.toolboxCategories.filter((category) =>
      category.blockTypes.some(
        (type) => loaded.blocksByType.get(type)?.toolboxVisible !== false,
      ),
    );

    expect(categories.map((category) => category.name)).toEqual(
      expected.map((category) => category.name),
    );
    categories.forEach((category, index) => {
      const firstVisibleType = expected[index].blockTypes.find(
        (type) => loaded.blocksByType.get(type)?.toolboxVisible !== false,
      );
      expect(category.colour).toBe(
        loaded.blocksByType.get(firstVisibleType as string)?.colour,
      );
    });
  });

  it("does not include or register toolbox search", () => {
    const toolbox = createToolbox(loaded);
    const workspaceSource = readFileSync(
      resolve(process.cwd(), "src/blockly/BlocklyWorkspace.tsx"),
      "utf8",
    );
    const packageJson = JSON.parse(
      readFileSync(resolve(process.cwd(), "package.json"), "utf8"),
    ) as { dependencies?: Record<string, string> };

    expect(toolbox.contents.some((item) => item.kind === "search")).toBe(false);
    expect(workspaceSource).not.toContain("@blockly/toolbox-search");
    expect(packageJson.dependencies).not.toHaveProperty("@blockly/toolbox-search");
  });

  it("registers the maintained continuous toolbox classes with Blockly", () => {
    const source = readFileSync(
      resolve(process.cwd(), "src/blockly/BlocklyWorkspace.tsx"),
      "utf8",
    );

    expect(source).toContain("ContinuousToolbox");
    expect(source).toContain("ContinuousFlyout");
    expect(source).toContain("ContinuousMetrics");
    expect(source).toContain("override getFlyoutScale(): number");
    expect(source).toMatch(/TUTORIAL_FLYOUT_SCALE\s*=\s*0\.65/);
    expect(source).toMatch(
      /flyoutsVerticalToolbox:\s*TutorialContinuousFlyout/,
    );
    expect(source).toMatch(/plugins:\s*continuousToolboxPlugins/);
  });
});
