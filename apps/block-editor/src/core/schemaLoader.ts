import type {
  LoadedTutorialSchema,
  TutorialBlockSchema,
  TutorialFieldSchema,
  TutorialNodeCatalog,
  TutorialSchema,
} from "./schemaTypes";

export function loadTutorialSchema(
  input: unknown,
  nodeCatalog?: unknown,
): LoadedTutorialSchema {
  assertSchema(input);
  const catalog = normalizeNodeCatalog(nodeCatalog);

  const blocksByType = new Map<string, TutorialBlockSchema>();
  const emitRulesByType = new Map();
  const connectionShapes = new Map(Object.entries(input.connectionShapes));
  const categoryMap = new Map<string, string[]>();

  for (const rawBlock of input.blocks) {
    const block = {
      ...rawBlock,
      fields: rawBlock.fields.map((field) => enrichField(field, catalog)),
    };
    if (blocksByType.has(block.type)) {
      throw new Error(`Duplicate tutorial block type: ${block.type}`);
    }
    blocksByType.set(block.type, block);
    emitRulesByType.set(block.type, block.emit);

    const current = categoryMap.get(block.category) ?? [];
    current.push(block.type);
    categoryMap.set(block.category, current);
  }

  return {
    blocksByType,
    emitRulesByType,
    connectionShapes,
    toolboxCategories: [...categoryMap.entries()].map(([name, blockTypes]) => ({
      name,
      blockTypes,
    })),
  };
}

function enrichField(
  field: TutorialFieldSchema,
  catalog: TutorialNodeCatalog | null,
): TutorialFieldSchema {
  if (field.type !== "node_type" || field.options || !catalog) {
    return field;
  }

  return {
    ...field,
    options: catalog.nodes.map((node) => ({
      label: node.label,
      value: node.id,
    })),
  };
}

function normalizeNodeCatalog(input: unknown): TutorialNodeCatalog | null {
  if (!input || typeof input !== "object") {
    return null;
  }
  const maybe = input as Partial<TutorialNodeCatalog>;
  if (!Array.isArray(maybe.nodes)) {
    return null;
  }
  return {
    schemaVersion: Number(maybe.schemaVersion ?? 1),
    nodes: maybe.nodes
      .filter((node) => node && typeof node === "object")
      .map((node) => {
        const record = node as Record<string, unknown>;
        return {
          id: String(record.id ?? ""),
          label: String(record.label ?? record.id ?? ""),
          runtimeLabel:
            record.runtimeLabel == null ? undefined : String(record.runtimeLabel),
        };
      })
      .filter((node) => node.id && node.label),
  };
}

function assertSchema(input: unknown): asserts input is TutorialSchema {
  if (!input || typeof input !== "object") {
    throw new Error("Tutorial schema must be an object");
  }
  const maybe = input as Partial<TutorialSchema>;
  if (!Array.isArray(maybe.blocks)) {
    throw new Error("Tutorial schema blocks must be an array");
  }
  if (!maybe.connectionShapes || typeof maybe.connectionShapes !== "object") {
    throw new Error("Tutorial schema connectionShapes must be an object");
  }
  for (const [check, shape] of Object.entries(maybe.connectionShapes)) {
    if (
      !shape ||
      typeof shape !== "object" ||
      !Number.isFinite(shape.width) ||
      !Number.isFinite(shape.height) ||
      !shape.pathLeft ||
      !shape.pathRight
    ) {
      throw new Error(`Connection shape '${check}' is invalid`);
    }
  }
  for (const block of maybe.blocks) {
    if (!block || typeof block !== "object") {
      throw new Error("Every block must be an object");
    }
    const b = block as Partial<TutorialBlockSchema>;
    if (!b.type || !b.message || !b.category || !b.emit) {
      throw new Error("Every block needs type, message, category, and emit");
    }
    if (!Array.isArray(b.fields)) {
      throw new Error(`Block '${b.type}' fields must be an array`);
    }
  }
}
