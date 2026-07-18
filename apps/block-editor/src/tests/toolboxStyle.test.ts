import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";

const css = readFileSync(resolve(process.cwd(), "src/app/App.css"), "utf8");

describe("Blockly toolbox style", () => {
  it("keeps a compact readable category rail without search styles", () => {
    expect(css).toMatch(/\.blocklyToolbox\s*\{[^}]*width:\s*84px/s);
    expect(css).toMatch(
      /\.blocklyTreeLabel,\s*\.blocklyToolboxCategoryLabel\s*\{[^}]*font-size:\s*9px[^}]*white-space:\s*nowrap/s,
    );
    expect(css).toMatch(/\.blocklyTreeSelected\s*\{[^}]*outline:\s*none !important/s);
    expect(css).not.toContain("#toolbox-search-input");
    expect(css).toMatch(/\.categoryBubble\s*\{[^}]*width:\s*22px[^}]*height:\s*22px/s);
    expect(css).toMatch(/\.blocklyFlyoutLabelText\s*\{[^}]*font-size:\s*15px/s);
  });
});
