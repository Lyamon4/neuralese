import { describe, expect, it } from "vitest";
import {
  createConnectionNotch,
  resolveConnectionNotch,
} from "../blockly/tutorialRenderer";

const shapes = new Map([
  [
    "action",
    {
      width: 36,
      height: 8,
      pathLeft: " h 8 l 4,8 h 12 l 4,-8 h 8 ",
      pathRight: " h -8 l -4,8 h -12 l -4,-8 h -8 ",
    },
  ],
  [
    "lesson_step",
    {
      width: 36,
      height: 8,
      pathLeft: " h 8 v 5 h 8 v -5 h 20 ",
      pathRight: " h -20 v 5 h -8 v -5 h -8 ",
    },
  ],
]);

describe("schema-driven connection shapes", () => {
  it("creates distinct notch geometry from schema definitions", () => {
    const action = createConnectionNotch(shapes.get("action")!, 5);
    const step = createConnectionNotch(shapes.get("lesson_step")!, 5);

    expect(action.pathLeft).not.toBe(step.pathLeft);
    expect(action.width).toBe(36);
    expect(step.height).toBe(8);
  });

  it("resolves matching checks and falls back for unknown checks", () => {
    const fallback = createConnectionNotch(shapes.get("action")!, 5);

    expect(resolveConnectionNotch(["lesson_step"], shapes, fallback).pathLeft).toContain("v 5");
    expect(resolveConnectionNotch(["unknown"], shapes, fallback)).toBe(fallback);
    expect(resolveConnectionNotch(null, shapes, fallback)).toBe(fallback);
  });
});
