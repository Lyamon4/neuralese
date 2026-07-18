import { describe, expect, it, vi } from "vitest";
import {
  collectBranchNames,
  createBranchReferenceConfig,
  createBranchReferenceOptions,
  refreshBranchReferenceFields,
} from "../blockly/branchReferences";
import { loadTutorialSchema } from "../core/schemaLoader";
import schema from "../schema/tutorialBlocks.schema.json";
import nodeCatalog from "../schema/tutorialNodeCatalog.json";

describe("schema-driven branch references", () => {
  it("discovers branch roots and goto fields from schema metadata", () => {
    const loaded = loadTutorialSchema(schema, nodeCatalog);
    const config = createBranchReferenceConfig(loaded);

    expect(config.branchRoots).toEqual([
      { blockType: "lesson_branch", nameField: "name" },
    ]);
    expect(config.references).toEqual(
      expect.arrayContaining([
        { blockType: "action_ask", fieldName: "default_branch", required: false },
        { blockType: "quiz_answer_route", fieldName: "branch", required: true },
      ]),
    );
  });

  it("collects unique valid branch names without hardcoded block types", () => {
    const blocks = [
      fakeBlock("custom_branch_root", "branch_name", "extra_help"),
      fakeBlock("custom_branch_root", "branch_name", "challenge"),
      fakeBlock("custom_branch_root", "branch_name", "extra_help"),
      fakeBlock("custom_branch_root", "branch_name", "flow"),
      fakeBlock("other", "branch_name", "ignored"),
    ];

    expect(
      collectBranchNames(
        { getAllBlocks: () => blocks } as never,
        [{ blockType: "custom_branch_root", nameField: "branch_name" }],
      ),
    ).toEqual(["challenge", "extra_help"]);
  });

  it("offers only existing branches and an empty option when the reference is optional", () => {
    expect(createBranchReferenceOptions(["challenge", "extra_help"], false)).toEqual([
      ["No branch", ""],
      ["challenge", "challenge"],
      ["extra_help", "extra_help"],
    ]);
    expect(createBranchReferenceOptions([], true)).toEqual([
      ["Create a branch first", ""],
    ]);
  });

  it("refreshes goto dropdowns from branch roots while preserving the selected name", () => {
    const setOptions = vi.fn();
    const setValue = vi.fn();
    const field = {
      getOptions: () => [["Create a branch first", ""]],
      getValue: () => "extra_help",
      setOptions,
      setValue,
    };
    const workspace = {
      getAllBlocks: () => [
        fakeBlock("custom_branch_root", "branch_name", "extra_help"),
        {
          type: "custom_ask",
          isInFlyout: false,
          getField: (name: string) => (name === "target" ? field : null),
        },
      ],
    };

    refreshBranchReferenceFields(workspace as never, {
      branchRoots: [
        { blockType: "custom_branch_root", nameField: "branch_name" },
      ],
      references: [
        { blockType: "custom_ask", fieldName: "target", required: true },
      ],
    });

    expect(setOptions).toHaveBeenCalledWith([["extra_help", "extra_help"]]);
    expect(setValue).toHaveBeenCalledWith("extra_help");
  });
});

function fakeBlock(type: string, fieldName: string, value: string) {
  return {
    type,
    isInFlyout: false,
    getFieldValue: (name: string) => (name === fieldName ? value : null),
  };
}
