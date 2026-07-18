import * as Blockly from "blockly";
import type { AstBlock, LessonAst } from "./lessonAst";

export function workspaceToLessonAst(
  workspace: Blockly.Workspace,
  meta: { bundleName: string; lessonKey: string; lessonTitle: string },
  rootBlockTypes: readonly string[],
  rootStackInputs: ReadonlyMap<string, string> = new Map(),
): LessonAst {
  const rootTypes = new Set(rootBlockTypes);
  const blocks = workspace
    .getTopBlocks(true)
    .filter((block) => !block.isInFlyout && rootTypes.has(block.type))
    .map((block) => workspaceBlockToAst(block, rootStackInputs.get(block.type)));

  return {
    bundleName: meta.bundleName,
    lessons: [
      {
        key: meta.lessonKey,
        title: meta.lessonTitle,
        blocks,
      },
    ],
  };
}

export function workspaceBlockToAst(
  block: Blockly.Block,
  nextStackInputName?: string,
): AstBlock {
  const fields: Record<string, unknown> = {};
  for (const input of block.inputList) {
    for (const field of input.fieldRow) {
      if (field.name) {
        fields[field.name] = field.getValue();
      }
    }
  }

  const inputs: Record<string, AstBlock[]> = {};
  for (const input of block.inputList) {
    const target = input.connection?.targetBlock();
    if (!input.name || !target) continue;
    inputs[input.name] = readBlockStack(target);
  }
  if (nextStackInputName) {
    const next = block.getNextBlock();
    if (next) {
      inputs[nextStackInputName] = readBlockStack(next);
    }
  }

  return {
    type: block.type,
    fields,
    inputs,
    children: Object.values(inputs).flat(),
  };
}

function readBlockStack(firstBlock: Blockly.Block): AstBlock[] {
  const blocks: AstBlock[] = [];
  let current: Blockly.Block | null = firstBlock;
  while (current) {
    blocks.push(workspaceBlockToAst(current));
    current = current.getNextBlock();
  }
  return blocks;
}
