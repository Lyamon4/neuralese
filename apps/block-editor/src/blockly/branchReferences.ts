import type * as Blockly from "blockly";
import type { LoadedTutorialSchema } from "../core/schemaTypes";

export type BranchRootDescriptor = {
  blockType: string;
  nameField: string;
};

export type BranchReferenceDescriptor = {
  blockType: string;
  fieldName: string;
  required: boolean;
};

export type BranchReferenceConfig = {
  branchRoots: BranchRootDescriptor[];
  references: BranchReferenceDescriptor[];
};

type DropdownField = {
  getOptions(useCache?: boolean): Array<[unknown, string]>;
  getValue(): unknown;
  setOptions(options: Array<[string, string]>): void;
  setValue(value: string): void;
};

export function createBranchReferenceConfig(
  loaded: LoadedTutorialSchema,
): BranchReferenceConfig {
  const branchRoots: BranchRootDescriptor[] = [];
  const references: BranchReferenceDescriptor[] = [];

  for (const block of loaded.blocksByType.values()) {
    if (block.role === "lesson_branch" && block.branchNameField) {
      branchRoots.push({
        blockType: block.type,
        nameField: block.branchNameField,
      });
    }
    for (const field of block.fields) {
      if (field.type !== "branch_ref") continue;
      references.push({
        blockType: block.type,
        fieldName: field.name,
        required: field.required === true,
      });
    }
  }

  return { branchRoots, references };
}

export function collectBranchNames(
  workspace: Pick<Blockly.Workspace, "getAllBlocks">,
  branchRoots: readonly BranchRootDescriptor[],
): string[] {
  const descriptorByType = new Map(
    branchRoots.map((descriptor) => [descriptor.blockType, descriptor]),
  );
  const names = new Set<string>();

  for (const block of workspace.getAllBlocks(false)) {
    if (block.isInFlyout) continue;
    const descriptor = descriptorByType.get(block.type);
    if (!descriptor) continue;
    const name = String(block.getFieldValue(descriptor.nameField) ?? "").trim();
    if (name && name !== "flow") names.add(name);
  }

  return [...names].sort((left, right) => left.localeCompare(right));
}

export function createBranchReferenceOptions(
  branchNames: readonly string[],
  required: boolean,
): Array<[string, string]> {
  if (branchNames.length === 0) {
    return [[required ? "Create a branch first" : "No branch", ""]];
  }
  const options = branchNames.map((name): [string, string] => [name, name]);
  return required ? options : [["No branch", ""], ...options];
}

export function refreshBranchReferenceFields(
  workspace: Pick<Blockly.Workspace, "getAllBlocks">,
  config: BranchReferenceConfig,
): void {
  const branchNames = collectBranchNames(workspace, config.branchRoots);
  const referencesByType = new Map<string, BranchReferenceDescriptor[]>();
  for (const reference of config.references) {
    const current = referencesByType.get(reference.blockType) ?? [];
    current.push(reference);
    referencesByType.set(reference.blockType, current);
  }

  for (const block of workspace.getAllBlocks(false)) {
    if (block.isInFlyout) continue;
    for (const reference of referencesByType.get(block.type) ?? []) {
      const field = block.getField(reference.fieldName) as DropdownField | null;
      if (!field || typeof field.setOptions !== "function") continue;

      const selected = String(field.getValue() ?? "");
      const options = createBranchReferenceOptions(branchNames, reference.required);
      if (selected && !branchNames.includes(selected)) {
        options.push([`Missing: ${selected}`, selected]);
      }
      if (sameOptions(field.getOptions(false), options)) continue;

      field.setOptions(options);
      if (options.some(([, value]) => value === selected)) {
        field.setValue(selected);
      }
    }
  }
}

function sameOptions(
  left: Array<[unknown, string]>,
  right: Array<[string, string]>,
): boolean {
  return (
    left.length === right.length &&
    left.every(
      ([label, value], index) =>
        String(label) === right[index][0] && value === right[index][1],
    )
  );
}
