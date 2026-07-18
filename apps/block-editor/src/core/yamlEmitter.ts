import type { EmitContext, SerializableBlock } from "./yamlEmitOps";

export function emitWorkspaceBlocksToYamlData(
  blocks: SerializableBlock[],
  emitRulesByType: Map<string, unknown>,
): unknown[] {
  return blocks.map((block) => emitBlockToYamlData(block, emitRulesByType));
}

export function emitBlockToYamlData(
  block: SerializableBlock,
  emitRulesByType: Map<string, unknown>,
): unknown {
  const rule = emitRulesByType.get(block.type);
  if (!rule) {
    throw new Error(`Missing emit rule for block type '${block.type}'`);
  }
  return evalEmitRule(rule, { block, emitRulesByType });
}

function evalEmitRule(rule: unknown, context: EmitContext): unknown {
  if (!isRecord(rule)) return rule;

  const op = String(rule.op ?? "literal");
  if (op === "literal") return rule.value;
  if (op === "field") {
    const value = context.block.fields[String(rule.name)] ?? rule.default;
    return coerceField(value, rule.coerce);
  }
  if (op === "template") return renderTemplate(String(rule.value ?? ""), context.block.fields);
  if (op === "children") {
    const inputName = typeof rule.input === "string" ? rule.input : "";
    const children = inputName
      ? context.block.inputs?.[inputName] ?? []
      : context.block.children;
    return children.map((child) => emitBlockToYamlData(child, context.emitRulesByType));
  }
  if (op === "childrenObject") {
    const children = context.block.inputs?.[String(rule.input)] ?? [];
    const out: Record<string, unknown> = {};
    for (const child of children) {
      const emitted = emitBlockToYamlData(child, context.emitRulesByType);
      if (!isRecord(emitted)) {
        throw new Error(`childrenObject expected '${child.type}' to emit an object`);
      }
      Object.assign(out, emitted);
    }
    return out;
  }
  if (op === "when") {
    const value = context.block.fields[String(rule.field)];
    const matches = rule.notEmpty
      ? value != null && String(value).trim() !== ""
      : value === rule.equals;
    if (matches) return evalEmitRule(rule.then, context);
    return rule.otherwise === undefined ? undefined : evalEmitRule(rule.otherwise, context);
  }
  if (op === "array") {
    return asArray(rule.items).map((item) => evalEmitRule(item, context));
  }
  if (op === "object") {
    const out: Record<string, unknown> = {};
    const fields = isRecord(rule.fields) ? rule.fields : {};
    for (const [keyTemplate, valueRule] of Object.entries(fields)) {
      const key = renderTemplate(keyTemplate, context.block.fields);
      const value = evalEmitRule(valueRule, context);
      if (value === undefined) continue;
      if (isRecord(valueRule) && valueRule.omitEmpty && isEmpty(value)) continue;
      out[key] = value;
    }
    return out;
  }
  if (op === "singleKeyMapping") {
    const key = String(evalEmitRule(rule.key, context));
    return { [key]: evalEmitRule(rule.value, context) };
  }
  if (op === "computedKey") {
    const key = renderTemplate(String(rule.template ?? ""), context.block.fields);
    return { [key]: evalEmitRule(rule.value, context) };
  }

  throw new Error(`Unknown emit op '${op}'`);
}

function renderTemplate(template: string, fields: Record<string, unknown>): string {
  return template.replace(/\{([a-zA-Z0-9_]+)\}/g, (_, name: string) =>
    String(fields[name] ?? ""),
  );
}

function isRecord(value: unknown): value is Record<string, any> {
  return !!value && typeof value === "object" && !Array.isArray(value);
}

function asArray(value: unknown): unknown[] {
  return Array.isArray(value) ? value : [];
}

function isEmpty(value: unknown): boolean {
  if (Array.isArray(value)) return value.length === 0;
  if (isRecord(value)) return Object.keys(value).length === 0;
  return value === "" || value == null;
}

function coerceField(value: unknown, coerce: unknown): unknown {
  if (coerce === "number") {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : undefined;
  }
  if (coerce === "boolean") {
    return value === true || value === "TRUE" || value === "true";
  }
  if (coerce === "lines") {
    return String(value ?? "")
      .split(/\r?\n/)
      .map((line) => line.trim())
      .filter(Boolean);
  }
  if (coerce === "integerList") {
    return String(value ?? "")
      .split(/[\n,]+/)
      .map((item) => Number.parseInt(item.trim(), 10))
      .filter(Number.isFinite);
  }
  return value;
}
