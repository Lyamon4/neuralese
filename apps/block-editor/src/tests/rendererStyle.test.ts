import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import {
  tutorialBlockStyles,
  tutorialLightBlockStyles,
  tutorialRendererOverrides,
  tutorialThemeCssVariables,
} from "../blockly/tutorialTheme";
import { TutorialConstantProvider } from "../blockly/tutorialRenderer";

const css = readFileSync(resolve(process.cwd(), "src/app/App.css"), "utf8");
const themeSource = readFileSync(
  resolve(process.cwd(), "src/blockly/tutorialTheme.ts"),
  "utf8",
);

describe("tutorial renderer style", () => {
  it("uses charcoal block fills with category accents on secondary colors", () => {
    expect(tutorialBlockStyles.lesson_blocks.colourPrimary).toBe("#202434");
    expect(tutorialBlockStyles.teacher_blocks.colourPrimary).toBe("#1d2b30");
    expect(tutorialBlockStyles.feedback_blocks.colourPrimary).toBe("#30231d");
    expect(tutorialBlockStyles.lesson_blocks.colourTertiary).toBe("#4b7dff");
    expect(tutorialBlockStyles.teacher_blocks.colourTertiary).toBe("#28c7e8");
    expect(tutorialRendererOverrides.CORNER_RADIUS).toBeGreaterThanOrEqual(9);
    expect(tutorialRendererOverrides.FIELD_BORDER_RECT_RADIUS).toBe(6);
  });

  it("loads dark and light palettes from data rather than TypeScript color literals", () => {
    expect(tutorialLightBlockStyles.lesson_blocks.colourPrimary).toBe("#b5c6ef");
    expect(tutorialLightBlockStyles.teacher_blocks.colourTertiary).toBe("#167f96");
    expect(tutorialThemeCssVariables.light["--block-text"]).toBe("#1b2631");
    expect(tutorialThemeCssVariables.light["--grid-dot"]).toBe("#c9ced3");
    expect(tutorialThemeCssVariables.light["--grid-image"]).toContain(
      "fill='%23c9ced3'",
    );
    expect(themeSource).not.toMatch(/#[0-9a-f]{3,8}/i);
  });

  it("keeps dropdown surface colors under theme CSS control", () => {
    const constants = new TutorialConstantProvider();
    expect(constants.FIELD_DROPDOWN_COLOURED_DIV).toBe(false);
    expect(constants.FIELD_DROPDOWN_SVG_ARROW).toBe(true);
  });

  it("uses Blockly's native cap style for main and branch roots", () => {
    expect(tutorialBlockStyles.lesson_hat_blocks).toMatchObject({
      colourPrimary: tutorialBlockStyles.lesson_blocks.colourPrimary,
      hat: "cap",
    });
    expect(tutorialBlockStyles.flow_hat_blocks).toMatchObject({
      colourPrimary: tutorialBlockStyles.flow_blocks.colourPrimary,
      hat: "cap",
    });
  });

  it("keeps field text readable and uses restrained blueprint highlights", () => {
    expect(css).toMatch(
      /\.blocklyEditableField\s*>\s*\.blocklyText[^{]*\{[^}]*fill:\s*#f1f5f9/s,
    );
    expect(css).toMatch(
      /\.blocklyHost\s+\.injectionDiv\s+\.blocklyDropdownField\s+\.blocklyDropdownText\s*\{[^}]*fill:\s*#f1f5f9 !important/s,
    );
    expect(css).toMatch(
      /html\s+body\s+\.blocklyDropDownDiv\s+\.blocklyMenuItem\s+\.blocklyMenuItemContent\s*\{[^}]*color:\s*#edf2f7 !important/s,
    );
    expect(css).toMatch(
      /\.blocklyHost\s+\.injectionDiv\s+\.blocklyDropdownField\s+\.blocklyDropdownArrow\s*\{[^}]*fill:\s*#aeb8c6 !important/s,
    );
    expect(css).toMatch(
      /\.blocklyEditableField:focus\s*>\s*\.blocklyFieldRect[^{]*\{[^}]*stroke:\s*rgba\(190,\s*203,\s*219,\s*0\.24\) !important/s,
    );
    expect(css).not.toContain(".blocklyHighlightedConnectionPath");
    expect(css).toMatch(
      /\.blocklyInsertionMarker\s*>\s*\.blocklyPath\s*\{[^}]*fill:\s*var\(--blockly-insertion-marker-accent,\s*#87919f\) !important;[^}]*fill-opacity:\s*0\.5 !important;[^}]*stroke:\s*var\(--blockly-insertion-marker-accent,\s*#87919f\) !important;[^}]*stroke-opacity:\s*0\.5 !important/s,
    );
    expect(css).toMatch(
      /\.blocklySelected\s*>\s*\.blocklyPath\s*\{[^}]*stroke-width:\s*1\.8px !important;[^}]*filter:\s*none !important/s,
    );
    expect(css).toMatch(
      /\.blocklySelected\s*>\s*\.blocklyPathSelected\s*\{[^}]*display:\s*none !important/s,
    );
    expect(css).toContain(
      ".blocklyDraggable:hover:not(:has(.blocklyField:hover)) > .blocklyPath",
    );
    expect(css).toMatch(
      /\.blocklyContextMenu::\s*-webkit-scrollbar,\s*\.blocklyWidgetDiv\s+\.blocklyMenu::\s*-webkit-scrollbar\s*\{[^}]*display:\s*none/s,
    );
    expect(css).toMatch(
      /\.blocklyOptionListActions\s*\{[^}]*grid-template-columns:\s*1fr auto auto/s,
    );
    expect(css).toContain(".blocklyOptionListButton.apply");
    expect(css).toMatch(
      /\.blocklyOptionListBullets\s*\{[^}]*pointer-events:\s*none/s,
    );
    expect(css).toMatch(
      /\.blocklyMenuItemSelected\.blocklyMenuItemHighlight\s*\{[^}]*background:\s*var\(--menu-selected\) !important/s,
    );
    expect(css).toMatch(
      /\.blocklyDropDownDiv\s+\.blocklyMenuItemContent\s*\{[^}]*background:\s*transparent !important;[^}]*box-shadow:\s*none !important/s,
    );
    expect(css).not.toContain("drop-shadow");
  });

  it("uses a sparse parallax workspace grid and export-blue ready state", () => {
    expect(css).toMatch(/\.readyState\s*\{[^}]*color:\s*#a9c2ff/s);
    expect(css).toMatch(/background-position:\s*var\(--workspace-grid-x,\s*0\) var\(--workspace-grid-y,\s*0\)/s);
    expect(css).toMatch(/background-size:\s*72px 72px/s);
    expect(css).not.toContain("radial-gradient");
  });
});
