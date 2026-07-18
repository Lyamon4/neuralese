import { describe, expect, it } from "vitest";
import schema from "../schema/tutorialBlocks.schema.json";

const REGISTERED_ACTIONS = [
  "explain",
  "hide_arrows",
  "arrow",
  "require",
  "create",
  "explain_button",
  "explain_next",
  "confetti",
  "select",
  "highlight",
  "ask",
  "multi_input",
  "prohibit_deletion",
  "allow_deletion",
];

const REGISTERED_REQUIREMENTS = [
  "node",
  "connection",
  "config",
  "topology",
  "wait",
  "event",
  "teacher_lock",
];

describe("tutorial DSL coverage", () => {
  it("uses one colour for every block in the same category", () => {
    const coloursByCategory = new Map<string, Set<string | number>>();
    for (const block of schema.blocks) {
      const colours = coloursByCategory.get(block.category) ?? new Set();
      colours.add(block.colour);
      coloursByCategory.set(block.category, colours);
    }

    for (const colours of coloursByCategory.values()) {
      expect(colours.size).toBe(1);
    }
  });

  it("has schema-defined blocks for every registered action", () => {
    const covered = new Set(
      schema.blocks
        .flatMap((block) => {
          if (!block.dsl) return [];
          return Array.isArray(block.dsl) ? block.dsl : [block.dsl];
        })
        .filter((entry) => entry.kind === "action")
        .map((entry) => entry.key),
    );

    expect([...covered].sort()).toEqual([...REGISTERED_ACTIONS].sort());
  });

  it("has schema-defined blocks for every registered requirement", () => {
    const covered = new Set(
      schema.blocks
        .flatMap((block) => {
          if (!block.dsl) return [];
          return Array.isArray(block.dsl) ? block.dsl : [block.dsl];
        })
        .filter((entry) => entry.kind === "requirement")
        .map((entry) => entry.key),
    );

    expect([...covered].sort()).toEqual([...REGISTERED_REQUIREMENTS].sort());
  });

  it("defines a visual shape for every connection check", () => {
    const checks = new Set<string>();

    for (const block of schema.blocks) {
      const connection = block.connection as
        | { previous?: string; next?: string; output?: string }
        | undefined;
      if (connection?.previous) checks.add(connection.previous);
      if (connection?.next) checks.add(connection.next);
      if (connection?.output) checks.add(connection.output);
      for (const input of block.statementInputs ?? []) {
        const inputChecks = Array.isArray(input.check) ? input.check : [input.check];
        inputChecks.forEach((check) => checks.add(check));
      }
    }

    expect(Object.keys(schema.connectionShapes).sort()).toEqual([...checks].sort());
  });
});
