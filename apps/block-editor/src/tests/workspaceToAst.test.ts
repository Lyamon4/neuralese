import { describe, expect, it } from "vitest";
import { workspaceToLessonAst } from "../core/workspaceToAst";

describe("workspace to lesson AST", () => {
  it("serializes step stacks connected below main and branch hat roots", () => {
    const mainStep = createBlock("lesson_step");
    const branchStep = createBlock("lesson_step");
    const root = createBlock("custom_lesson_root", mainStep);
    const branch = createBlock("custom_lesson_branch", branchStep);
    const detached = createBlock("action_explain");
    const workspace = {
      getTopBlocks: () => [root, branch, detached],
    };

    const ast = workspaceToLessonAst(
      workspace as never,
      {
        bundleName: "Course",
        lessonKey: "intro",
        lessonTitle: "Intro",
      },
      ["custom_lesson_root", "custom_lesson_branch"],
      new Map([
        ["custom_lesson_root", "flow"],
        ["custom_lesson_branch", "steps"],
      ]),
    );

    expect(ast.lessons[0].blocks[0].inputs.flow).toEqual([
      expect.objectContaining({ type: "lesson_step" }),
    ]);
    expect(ast.lessons[0].blocks[1].inputs.steps).toEqual([
      expect.objectContaining({ type: "lesson_step" }),
    ]);
  });
});

type FakeBlock = {
  type: string;
  isInFlyout: boolean;
  inputList: [];
  getNextBlock: () => FakeBlock | null;
};

function createBlock(type: string, next: FakeBlock | null = null): FakeBlock {
  return {
    type,
    isInFlyout: false,
    inputList: [],
    getNextBlock: () => next,
  };
}
