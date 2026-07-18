import type { AstBlock, LessonAst } from "./lessonAst";
import type { ConnectionCheck, LoadedTutorialSchema } from "./schemaTypes";
import { emitBlockToYamlData } from "./yamlEmitter";

export type ValidationIssue = {
  path: string;
  message: string;
};

export function validateLessonAst(
  ast: LessonAst,
  loaded: LoadedTutorialSchema,
): ValidationIssue[] {
  const issues: ValidationIssue[] = [];

  if (!ast.bundleName.trim()) {
    issues.push({ path: "bundle.name", message: "Add a bundle name." });
  }
  if (ast.lessons.length === 0) {
    issues.push({ path: "lessons", message: "Add at least one workspace." });
  }

  for (const lesson of ast.lessons) {
    if (!lesson.key.trim()) {
      issues.push({ path: "lesson.key", message: "Workspace needs an internal key." });
    }
    if (!lesson.title.trim()) {
      issues.push({ path: `lesson.${lesson.key}.title`, message: "Workspace needs a title." });
    }
    if (lesson.blocks.length === 0) {
      issues.push({
        path: `lesson.${lesson.key}.blocks`,
        message: "Each workspace must contain exactly one main-flow root block.",
      });
    }

    const mainRoots = lesson.blocks.filter(
      (block) => loaded.blocksByType.get(block.type)?.role === "lesson_root",
    );
    if (mainRoots.length !== 1) {
      issues.push({
        path: `lesson.${lesson.key}.root`,
        message: "Each workspace must contain exactly one main-flow root block.",
      });
    }

    const branchNames = new Set<string>();
    const duplicateBranchNames = new Set<string>();
    const branchRoots = lesson.blocks.filter(
      (block) => loaded.blocksByType.get(block.type)?.role === "lesson_branch",
    );
    for (const branchRoot of branchRoots) {
      const emitted = emitBlockSafely(branchRoot, loaded);
      if (!isRecord(emitted) || Object.keys(emitted).length !== 1) continue;
      const [name] = Object.keys(emitted);
      if (!name.trim()) continue;
      if (name === "flow") {
        issues.push({
          path: `lesson.${lesson.key}.branch.${name}`,
          message: "Branch name 'flow' is reserved.",
        });
      }
      if (branchNames.has(name) && !duplicateBranchNames.has(name)) {
        duplicateBranchNames.add(name);
        issues.push({
          path: `lesson.${lesson.key}.branch.${name}`,
          message: `Branch name '${name}' is used more than once.`,
        });
      }
      branchNames.add(name);
    }

    for (const block of lesson.blocks) {
      const schema = loaded.blocksByType.get(block.type);
      if (!schema) {
        issues.push({ path: block.type, message: `Unknown block type: ${block.type}` });
        continue;
      }
      if (schema.role !== "lesson_root" && schema.role !== "lesson_branch") {
        issues.push({
          path: block.type,
          message: "Only main-flow and branch root blocks can be placed at the top level.",
        });
      }
      validateBlock(block, loaded, issues, block.type);
    }

    validateNamedSymbols(
      lesson.blocks,
      loaded,
      issues,
      `lesson.${lesson.key}`,
    );

    const gotoTargets = new Set<string>();
    for (const root of [...mainRoots, ...branchRoots]) {
      collectGotoTargets(emitBlockSafely(root, loaded), gotoTargets);
    }
    for (const target of gotoTargets) {
      if (!branchNames.has(target)) {
        issues.push({
          path: `lesson.${lesson.key}.goto.${target}`,
          message: `Goto references unknown branch '${target}'.`,
        });
      }
    }
  }

  return issues;
}

type SymbolOccurrence = {
  namespace: string;
  name: string;
  path: string;
};

function validateNamedSymbols(
  roots: AstBlock[],
  loaded: LoadedTutorialSchema,
  issues: ValidationIssue[],
  lessonPath: string,
): void {
  const definitions = new Map<string, SymbolOccurrence[]>();
  const references = new Map<string, SymbolOccurrence[]>();

  for (const root of roots) {
    collectNamedSymbols(
      root,
      loaded,
      definitions,
      references,
      `${lessonPath}.${root.type}`,
    );
  }

  for (const occurrences of definitions.values()) {
    if (occurrences.length < 2) continue;
    const [{ namespace, name, path }] = occurrences;
    issues.push({
      path,
      message: `${formatSymbolNamespace(namespace)} '${name}' is created by more than one block.`,
    });
  }

  for (const [key, occurrences] of references) {
    if (definitions.has(key)) continue;
    const [{ namespace, name, path }] = occurrences;
    issues.push({
      path,
      message: `${formatSymbolNamespace(namespace)} '${name}' is referenced but never created.`,
    });
  }
}

function collectNamedSymbols(
  block: AstBlock,
  loaded: LoadedTutorialSchema,
  definitions: Map<string, SymbolOccurrence[]>,
  references: Map<string, SymbolOccurrence[]>,
  path: string,
): void {
  const schema = loaded.blocksByType.get(block.type);
  if (!schema) return;

  for (const field of schema.fields) {
    if (!field.symbol) continue;
    if (field.visibleWhen && !fieldVisibilityMatches(block, field.visibleWhen)) {
      continue;
    }
    const name = String(block.fields[field.name] ?? "").trim();
    if (!name) continue;
    const occurrence = {
      namespace: field.symbol.namespace,
      name,
      path: `${path}.${field.name}`,
    };
    const symbols =
      field.symbol.role === "definition" ? definitions : references;
    const key = symbolKey(field.symbol.namespace, name);
    symbols.set(key, [...(symbols.get(key) ?? []), occurrence]);
  }

  for (const [inputName, children] of Object.entries(block.inputs)) {
    children.forEach((child, index) =>
      collectNamedSymbols(
        child,
        loaded,
        definitions,
        references,
        `${path}.${inputName}.${index}.${child.type}`,
      ),
    );
  }
}

function symbolKey(namespace: string, name: string): string {
  return `${namespace}\u0000${name}`;
}

function formatSymbolNamespace(namespace: string): string {
  return namespace.charAt(0).toUpperCase() + namespace.slice(1);
}

export function assertLessonAstValid(ast: LessonAst, loaded: LoadedTutorialSchema): void {
  const issues = validateLessonAst(ast, loaded);
  if (issues.length > 0) {
    throw new Error(issues.map((issue) => issue.message).join("\n"));
  }
}

function validateBlock(
  block: AstBlock,
  loaded: LoadedTutorialSchema,
  issues: ValidationIssue[],
  path: string,
): void {
  const schema = loaded.blocksByType.get(block.type);
  if (!schema) return;

  for (const field of schema.fields) {
    if (!field.required) continue;
    if (field.visibleWhen && !fieldVisibilityMatches(block, field.visibleWhen)) continue;
    const value = block.fields[field.name];
    if (value == null || String(value).trim() === "") {
      issues.push({
        path: `${path}.${field.name}`,
        message: `${field.label} is required.`,
      });
    }
  }

  for (const input of schema.statementInputs ?? []) {
    const children = block.inputs[input.name] ?? [];
    if (input.required && children.length === 0) {
      issues.push({
        path: `${path}.${input.name}`,
        message: `${input.label} needs at least one block.`,
      });
    }
    for (const child of children) {
      if (!blockMatchesConnection(child, input.check, loaded)) {
        issues.push({
          path: `${path}.${input.name}.${child.type}`,
          message: `Only ${formatCheck(input.check)} blocks can be placed inside ${input.label}.`,
        });
      }
      validateBlock(child, loaded, issues, `${path}.${input.name}.${child.type}`);
    }
  }

  if (schema.stackInput) {
    const children = block.inputs[schema.stackInput] ?? [];
    if (children.length === 0) {
      issues.push({
        path: `${path}.${schema.stackInput}`,
        message: `${formatStackInput(schema.stackInput)} needs at least one block.`,
      });
    }
    for (const child of children) {
      if (
        schema.connection?.next &&
        !blockMatchesConnection(child, schema.connection.next, loaded)
      ) {
        issues.push({
          path: `${path}.${schema.stackInput}.${child.type}`,
          message: `Only ${formatCheck(schema.connection.next)} blocks can be placed under ${formatStackInput(schema.stackInput)}.`,
        });
      }
      validateBlock(child, loaded, issues, `${path}.${schema.stackInput}.${child.type}`);
    }
  }
}

function fieldVisibilityMatches(
  block: AstBlock,
  rule: { field: string; equals?: unknown; notEmpty?: boolean },
): boolean {
  const value = block.fields[rule.field];
  if (rule.notEmpty) {
    return value != null && String(value).trim() !== "";
  }
  return value === rule.equals;
}

function blockMatchesConnection(
  block: AstBlock,
  expected: ConnectionCheck | ConnectionCheck[],
  loaded: LoadedTutorialSchema,
): boolean {
  const schema = loaded.blocksByType.get(block.type);
  const previous = schema?.connection?.previous;
  const checks = Array.isArray(expected) ? expected : [expected];
  return previous != null && checks.includes(previous);
}

function formatCheck(check: ConnectionCheck | ConnectionCheck[]): string {
  return Array.isArray(check) ? check.join(" or ") : check;
}

function formatStackInput(inputName: string): string {
  return inputName
    .split("_")
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(" ");
}

function emitBlockSafely(block: AstBlock, loaded: LoadedTutorialSchema): unknown {
  try {
    return emitBlockToYamlData(block, loaded.emitRulesByType);
  } catch {
    return undefined;
  }
}

function collectGotoTargets(value: unknown, targets: Set<string>): void {
  if (Array.isArray(value)) {
    value.forEach((item) => collectGotoTargets(item, targets));
    return;
  }
  if (!isRecord(value)) return;
  if (
    Object.keys(value).length === 1 &&
    typeof value.goto === "string" &&
    value.goto.trim()
  ) {
    targets.add(value.goto.trim());
    return;
  }
  Object.values(value).forEach((item) => collectGotoTargets(item, targets));
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return !!value && typeof value === "object" && !Array.isArray(value);
}
