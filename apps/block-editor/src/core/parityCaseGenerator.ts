import type { AstBlock, LessonAst } from "./lessonAst";
import type {
  LoadedTutorialSchema,
  StatementInputSchema,
  TutorialBlockSchema,
  TutorialFieldSchema,
} from "./schemaTypes";
import { validateLessonAst } from "./syntaxGuardrails";

export type SyntaxParityCase = {
  id: string;
  description: string;
  ast: LessonAst;
  coveredBlockTypes: string[];
};

type BlockVariant = {
  id: string;
  description: string;
  block: AstBlock;
};

export function generateSyntaxParityCases(
  loaded: LoadedTutorialSchema,
): SyntaxParityCase[] {
  const actionDefinitions = [...loaded.blocksByType.values()].filter(
    (block) => connectionAccepts(block.connection?.previous, "action"),
  );
  if (actionDefinitions.length === 0) {
    throw new Error("The tutorial schema defines no action blocks");
  }

  const cases: SyntaxParityCase[] = [];
  for (const definition of actionDefinitions) {
    for (const variant of generateBlockVariants(definition, loaded, [])) {
      cases.push(
        createCase(
          `${definition.type}__${variant.id}`,
          `${definition.type}: ${variant.description}`,
          [variant.block],
          loaded,
        ),
      );
    }
  }

  cases.push(
    createCase(
      "all_actions",
      "all action blocks in one action sequence",
      actionDefinitions.map((definition) =>
        createBaselineBlock(definition, loaded, []),
      ),
      loaded,
    ),
  );
  cases.push(
    createCase(
      "persistent_step",
      "persistent lesson step",
      [
        createBaselineBlock(
          requiredBlock(loaded, "action_explain_next"),
          loaded,
          [],
        ),
      ],
      loaded,
      true,
    ),
  );

  const deduplicated = deduplicateCases(cases);
  assertParityCasesPassGuardrails(deduplicated, loaded);
  return deduplicated;
}

function generateBlockVariants(
  definition: TutorialBlockSchema,
  loaded: LoadedTutorialSchema,
  ancestors: string[],
): BlockVariant[] {
  if (ancestors.includes(definition.type)) {
    throw new Error(
      `Recursive statement-input cycle: ${[...ancestors, definition.type].join(" -> ")}`,
    );
  }
  const nextAncestors = [...ancestors, definition.type];
  const baseline = createBaselineBlock(definition, loaded, nextAncestors);
  const variants: BlockVariant[] = [
    { id: "default", description: "default fields and required inputs", block: baseline },
  ];

  for (const field of definition.fields) {
    for (const value of fieldVariantValues(field, baseline.fields[field.name])) {
      let variantBlock = withField(baseline, field.name, value);
      if (field.visibleWhen) {
        const controllingValue = field.visibleWhen.notEmpty
          ? nonEmptyValue(variantBlock.fields[field.visibleWhen.field])
          : field.visibleWhen.equals;
        variantBlock = withField(
          variantBlock,
          field.visibleWhen.field,
          controllingValue,
        );
      }
      variants.push({
        id: `field_${safeId(field.name)}_${safeValueId(value)}`,
        description: `${field.name} = ${JSON.stringify(value)}`,
        block: variantBlock,
      });
    }
  }

  for (const input of definition.statementInputs ?? []) {
    const compatible = compatibleDefinitions(input, loaded);
    if (compatible.length === 0) {
      throw new Error(
        `No block can satisfy input '${definition.type}.${input.name}'`,
      );
    }

    for (const childDefinition of compatible) {
      const childVariants = generateBlockVariants(
        childDefinition,
        loaded,
        nextAncestors,
      );
      for (const childVariant of childVariants) {
        const withChild = withInput(
          baseline,
          input.name,
          [childVariant.block],
        );
        variants.push({
          id: `input_${safeId(input.name)}_${safeId(childDefinition.type)}_${childVariant.id}`,
          description: `${input.name} contains ${childDefinition.type} (${childVariant.description})`,
          block: addInputDependencies(
            definition,
            input,
            withChild,
            childVariant.block,
            loaded,
          ),
        });
      }
    }
  }

  return variants;
}

function createBaselineBlock(
  definition: TutorialBlockSchema,
  loaded: LoadedTutorialSchema,
  ancestors: string[],
): AstBlock {
  const fields = Object.fromEntries(
    definition.fields.map((field, index) => [
      field.name,
      baselineFieldValue(field, definition.type, index),
    ]),
  );
  const inputs: Record<string, AstBlock[]> = {};

  for (const input of definition.statementInputs ?? []) {
    if (!input.required) {
      inputs[input.name] = [];
      continue;
    }
    const [childDefinition] = compatibleDefinitions(input, loaded);
    if (!childDefinition) {
      throw new Error(
        `No block can satisfy required input '${definition.type}.${input.name}'`,
      );
    }
    inputs[input.name] = [
      createBaselineBlock(childDefinition, loaded, [
        ...ancestors,
        childDefinition.type,
      ]),
    ];
  }

  return {
    type: definition.type,
    fields,
    children: [],
    inputs,
  };
}

function compatibleDefinitions(
  input: StatementInputSchema,
  loaded: LoadedTutorialSchema,
): TutorialBlockSchema[] {
  const accepted = new Set(Array.isArray(input.check) ? input.check : [input.check]);
  return [...loaded.blocksByType.values()].filter((candidate) => {
    const previous = candidate.connection?.previous;
    return previous != null && accepted.has(previous);
  });
}

function baselineFieldValue(
  field: TutorialFieldSchema,
  blockType: string,
  index: number,
): unknown {
  if (field.type === "bool" && field.default !== undefined) {
    return field.default === true || field.default === "TRUE" ? "TRUE" : "FALSE";
  }
  if (field.default !== undefined) return field.default;
  if (field.options?.length) return field.options[0].value;

  switch (field.type) {
    case "bool":
      return "FALSE";
    case "number":
      return field.min ?? 1;
    case "slug":
    case "node_alias":
      return `${safeId(blockType)}_${safeId(field.name)}_${index + 1}`;
    case "node_type":
      return "layer";
    case "event_name":
      return "ui_mouse_middle";
    case "wait_mode":
      return "next";
    case "option_list":
      return "First option\nSecond option";
    case "string_list":
      return "generated_1";
    case "textarea":
    case "text":
      return `Generated ${field.label}`;
    case "label":
      return field.label;
    case "branch_ref":
      return "";
    case "config_expr":
      return "8";
    case "edge_list":
      return "input:0 -> dense:0";
    case "select":
      throw new Error(
        `Select field '${blockType}.${field.name}' has no options or default`,
      );
  }
}

function fieldVariantValues(
  field: TutorialFieldSchema,
  baseline: unknown,
): unknown[] {
  const values: unknown[] = [];
  if (field.options) values.push(...field.options.map((option) => option.value));
  if (field.type === "bool") values.push("TRUE", "FALSE");
  if (field.type === "branch_ref") values.push("extra_help");
  if (field.type === "number") {
    if (field.min !== undefined) values.push(field.min);
    if (field.max !== undefined) values.push(field.max);
    if ((field.precision ?? 1) < 1) values.push(2.5);
  }
  return [...new Map(values.map((value) => [JSON.stringify(value), value])).values()]
    .filter((value) => !Object.is(value, baseline));
}

function createCase(
  id: string,
  description: string,
  actions: AstBlock[],
  loaded: LoadedTutorialSchema,
  persistent = false,
): SyntaxParityCase {
  const validActions = satisfyNamedSymbols(actions, loaded);
  const mainStep = createLessonStep("main", validActions, persistent);
  const branchStep = createLessonStep("branch", [
    createBaselineBlock(
      requiredBlock(loaded, "action_explain_next"),
      loaded,
      ["action_explain_next"],
    ),
  ]);
  const blocks: AstBlock[] = [
    {
      type: "lesson_root",
      fields: {},
      children: [],
      inputs: { flow: [mainStep] },
    },
    {
      type: "lesson_branch",
      fields: { name: "extra_help" },
      children: [],
      inputs: { steps: [branchStep] },
    },
  ];

  return {
    id: safeId(id),
    description,
    ast: {
      bundleName: `Syntax parity: ${description}`,
      lessons: [
        {
          key: "generated",
          title: description,
          blocks,
        },
      ],
    },
    coveredBlockTypes: [...collectBlockTypes(blocks)].sort(),
  };
}

type SymbolOccurrence = {
  namespace: string;
  name: string;
};

function satisfyNamedSymbols(
  actions: AstBlock[],
  loaded: LoadedTutorialSchema,
): AstBlock[] {
  const normalized = actions.map(cloneAstBlock);
  const definitions = new Map<string, SymbolOccurrence>();
  const references = new Map<string, SymbolOccurrence>();

  visitBlocks(normalized, (block) => {
    const schema = loaded.blocksByType.get(block.type);
    if (!schema) return;
    for (const field of schema.fields) {
      if (!field.symbol) continue;
      const name = String(block.fields[field.name] ?? "").trim();
      if (!name) continue;
      const key = symbolKey(field.symbol.namespace, name);
      if (field.symbol.role === "reference") {
        references.set(key, { namespace: field.symbol.namespace, name });
        continue;
      }
      if (!definitions.has(key)) {
        definitions.set(key, { namespace: field.symbol.namespace, name });
        continue;
      }

      const uniqueName = nextAvailableSymbolName(
        field.symbol.namespace,
        name,
        definitions,
      );
      block.fields[field.name] = uniqueName;
      definitions.set(symbolKey(field.symbol.namespace, uniqueName), {
        namespace: field.symbol.namespace,
        name: uniqueName,
      });
    }
  });

  const scaffolds: AstBlock[] = [];
  for (const [key, reference] of references) {
    if (definitions.has(key)) continue;
    const { definition, field } = findActionSymbolDefinition(
      reference.namespace,
      loaded,
    );
    const scaffold = createBaselineBlock(definition, loaded, []);
    scaffold.fields[field.name] = reference.name;
    scaffolds.push(scaffold);
    definitions.set(key, reference);
  }

  return [...scaffolds, ...normalized];
}

function findActionSymbolDefinition(
  namespace: string,
  loaded: LoadedTutorialSchema,
): { definition: TutorialBlockSchema; field: TutorialFieldSchema } {
  for (const definition of loaded.blocksByType.values()) {
    if (!connectionAccepts(definition.connection?.previous, "action")) continue;
    const field = definition.fields.find(
      (candidate) =>
        candidate.symbol?.namespace === namespace &&
        candidate.symbol.role === "definition",
    );
    if (field) return { definition, field };
  }
  throw new Error(
    `No action block defines symbols in namespace '${namespace}'`,
  );
}

function nextAvailableSymbolName(
  namespace: string,
  baseName: string,
  definitions: ReadonlyMap<string, SymbolOccurrence>,
): string {
  let suffix = 2;
  let candidate = `${baseName}_${suffix}`;
  while (definitions.has(symbolKey(namespace, candidate))) {
    suffix += 1;
    candidate = `${baseName}_${suffix}`;
  }
  return candidate;
}

function symbolKey(namespace: string, name: string): string {
  return `${namespace}\u0000${name}`;
}

function cloneAstBlock(block: AstBlock): AstBlock {
  const inputs = Object.fromEntries(
    Object.entries(block.inputs).map(([name, children]) => [
      name,
      children.map(cloneAstBlock),
    ]),
  );
  return {
    ...block,
    fields: { ...block.fields },
    inputs,
    children: Object.values(inputs).flat(),
  };
}

function visitBlocks(
  blocks: AstBlock[],
  visit: (block: AstBlock) => void,
): void {
  for (const block of blocks) {
    visit(block);
    visitBlocks(Object.values(block.inputs).flat(), visit);
  }
}

function assertParityCasesPassGuardrails(
  cases: SyntaxParityCase[],
  loaded: LoadedTutorialSchema,
): void {
  for (const testCase of cases) {
    const issues = validateLessonAst(testCase.ast, loaded);
    if (issues.length === 0) continue;
    throw new Error(
      `Generated syntax parity case '${testCase.id}' failed editor guardrails:\n${issues
        .map((issue) => `- ${issue.path}: ${issue.message}`)
        .join("\n")}`,
    );
  }
}

function createLessonStep(
  id: string,
  actions: AstBlock[],
  persistent = false,
): AstBlock {
  return {
    type: "lesson_step",
    fields: {
      id: `generated_${id}`,
      title: `Generated ${id} step`,
      persistent: persistent ? "TRUE" : "FALSE",
    },
    children: [],
    inputs: { actions },
  };
}

function requiredBlock(
  loaded: LoadedTutorialSchema,
  type: string,
): TutorialBlockSchema {
  const definition = loaded.blocksByType.get(type);
  if (!definition) throw new Error(`Required parity scaffold block '${type}' is missing`);
  return definition;
}

function withField(block: AstBlock, name: string, value: unknown): AstBlock {
  return {
    ...block,
    fields: { ...block.fields, [name]: value },
  };
}

function withInput(
  block: AstBlock,
  name: string,
  children: AstBlock[],
): AstBlock {
  return {
    ...block,
    inputs: { ...block.inputs, [name]: children },
  };
}

function addInputDependencies(
  parentDefinition: TutorialBlockSchema,
  input: StatementInputSchema,
  parent: AstBlock,
  child: AstBlock,
  loaded: LoadedTutorialSchema,
): AstBlock {
  if (
    parentDefinition.type !== "action_require_topology" ||
    input.name !== "edges" ||
    child.type !== "topology_edge"
  ) {
    return parent;
  }

  const topologyNode = requiredBlock(loaded, "topology_node");
  const aliases = [
    String(parent.fields.root ?? "").trim(),
    String(child.fields.from ?? "").trim(),
    String(child.fields.to ?? "").trim(),
  ].filter(Boolean);
  const existing = parent.inputs.nodes ?? [];
  const byAlias = new Map(
    existing.map((node) => [String(node.fields.alias ?? ""), node]),
  );
  for (const alias of aliases) {
    if (byAlias.has(alias)) continue;
    const node = createBaselineBlock(topologyNode, loaded, []);
    byAlias.set(alias, {
      ...node,
      fields: {
        ...node.fields,
        alias,
        node_type: alias === "input" ? "input" : node.fields.node_type,
      },
    });
  }
  return withInput(parent, "nodes", [...byAlias.values()]);
}

function collectBlockTypes(blocks: AstBlock[]): Set<string> {
  const types = new Set<string>();
  const visit = (block: AstBlock) => {
    types.add(block.type);
    Object.values(block.inputs).flat().forEach(visit);
  };
  blocks.forEach(visit);
  return types;
}

function deduplicateCases(cases: SyntaxParityCase[]): SyntaxParityCase[] {
  const seen = new Set<string>();
  return cases.filter((testCase) => {
    const signature = JSON.stringify(testCase.ast);
    if (seen.has(signature)) return false;
    seen.add(signature);
    return true;
  });
}

function connectionAccepts(
  actual: string | null | undefined,
  expected: string,
): boolean {
  return actual === expected;
}

function safeId(value: unknown): string {
  return (
    String(value)
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "_")
      .replace(/^_+|_+$/g, "") || "empty"
  );
}

function safeValueId(value: unknown): string {
  const raw = String(value);
  const normalized = safeId(raw);
  const readable = normalized === "empty" && raw !== "" ? "symbol" : normalized;
  let hash = 2166136261;
  for (const character of raw) {
    hash ^= character.codePointAt(0) ?? 0;
    hash = Math.imul(hash, 16777619);
  }
  return `${readable}_${(hash >>> 0).toString(36)}`;
}

function nonEmptyValue(value: unknown): unknown {
  return value == null || String(value).trim() === "" ? "generated" : value;
}
