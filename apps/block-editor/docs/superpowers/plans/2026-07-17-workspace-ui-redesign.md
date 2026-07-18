# Workspace UI Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace lesson-facing UI with named workspaces, simplify the editor layout, and add Scratch-style continuous Blockly category navigation without changing exported YAML bundles.

**Architecture:** Keep `LessonDraft`, `LessonAst`, and the bundle exporter as the compatibility boundary. Add focused workspace naming helpers around the existing draft model, keep React responsible for panel/dialog state, and use Blockly's maintained continuous-toolbox plugin rather than custom scroll synchronization.

**Tech Stack:** React 19, TypeScript 5.7, Blockly 12, `@blockly/continuous-toolbox`, Vitest, Testing Library, Playwright, JSZip.

## Global Constraints

- UI terminology uses `Workspace`; serialized bundle terminology remains `lesson`.
- Exports remain `bundle.yaml` plus `lessons/<key>.yaml`.
- Block types, categories, and YAML mappings continue to come from the JSON schema.
- A bundle always contains at least one workspace.
- Workspace keys are generated from names and remain unique.
- Existing syntax-parity and bundle-export behavior must not change.

---

### Task 1: Workspace naming model

**Files:**
- Modify: `src/core/lessonDrafts.ts`
- Modify: `src/tests/lessonDrafts.test.ts`

**Interfaces:**
- Produces: `workspaceKeyFromName(name: string): string`
- Produces: `createWorkspaceKey(drafts: Array<Pick<LessonDraft, "key">>, name: string): string`
- Existing `createLessonDraft(key, title)` remains the internal draft constructor.

- [ ] **Step 1: Write failing naming tests**

Add tests asserting that `"My First Model"` becomes `my_first_model`, punctuation is removed, an empty normalized name falls back to `workspace`, and collisions produce `_2`, `_3` suffixes.

- [ ] **Step 2: Run the focused test and verify RED**

Run: `npm test -- src/tests/lessonDrafts.test.ts`

Expected: failure because `workspaceKeyFromName` and `createWorkspaceKey` do not exist.

- [ ] **Step 3: Implement the minimal helpers**

Use the existing lowercase/underscore rules and `createLessonKey` collision logic:

```ts
export function workspaceKeyFromName(name: string): string {
  return normalize(name) || "workspace";
}

export function createWorkspaceKey(
  drafts: Array<Pick<LessonDraft, "key">>,
  name: string,
): string {
  return createLessonKey(drafts, workspaceKeyFromName(name));
}
```

- [ ] **Step 4: Run the focused test and verify GREEN**

Run: `npm test -- src/tests/lessonDrafts.test.ts`

Expected: all lesson draft tests pass.

### Task 2: Workspace-oriented app shell

**Files:**
- Create: `src/app/WorkspaceDialog.tsx`
- Modify: `src/app/App.tsx`
- Modify: `src/app/App.css`
- Modify: `src/tests/App.test.tsx`

**Interfaces:**
- `WorkspaceDialog` consumes `open`, `onCancel`, and `onCreate(name)`.
- `App` keeps `LessonDraft[]` internally while rendering Workspaces.

- [ ] **Step 1: Replace App tests with failing workspace behavior tests**

Cover creation dialog, generated key, workspace row metadata, one-workspace deletion guard, panel-local collapse button, edge restore button, moved Export files, removed Lesson panel, and top validation trigger.

- [ ] **Step 2: Run App tests and verify RED**

Run: `npm test -- src/tests/App.test.tsx`

Expected: failures for missing Workspace labels/dialog/buttons.

- [ ] **Step 3: Implement the creation dialog and workspace state transitions**

The plus button opens the dialog. `onCreate` trims the name, calls `createWorkspaceKey`, creates the internal draft, selects it, and closes the dialog. Renaming is not exposed elsewhere.

- [ ] **Step 4: Recompose the panels**

Remove the right panel. Put Workspaces and Export files inside Bundle, move collapse into the Bundle title row, add the left edge restore tab, and add the expandable warning trigger below the top bar.

- [ ] **Step 5: Style the new layout**

Use a two-column layout (`Bundle + Blockly`) when open and a single Blockly column when closed. Workspace rows show title, key, and block count with stable dimensions and blue selection. Keep the dialog compact and keyboard accessible.

- [ ] **Step 6: Run App tests and verify GREEN**

Run: `npm test -- src/tests/App.test.tsx`

Expected: all App tests pass.

### Task 3: Continuous Scratch-style toolbox

**Files:**
- Modify: `package.json`
- Modify: `package-lock.json`
- Modify: `src/blockly/BlocklyWorkspace.tsx`
- Modify: `src/blockly/createToolbox.ts`
- Modify: `src/app/App.css`
- Modify: `src/tests/toolboxStyle.test.ts`
- Create: `src/tests/continuousToolbox.test.ts`

**Interfaces:**
- `createToolbox` still derives all category names and blocks from `LoadedTutorialSchema`.
- Blockly injection receives `ContinuousToolbox`, `ContinuousFlyout`, and `ContinuousMetrics` plugins.

- [ ] **Step 1: Add failing toolbox contract tests**

Assert that each schema category carries its schema color/style metadata and remains in schema order. Add a source-level contract test proving the continuous toolbox plugin classes are supplied to Blockly injection.

- [ ] **Step 2: Run focused tests and verify RED**

Run: `npm test -- src/tests/continuousToolbox.test.ts src/tests/toolboxStyle.test.ts`

Expected: failure because the plugin and category color metadata are absent.

- [ ] **Step 3: Install and register the maintained plugin**

Run: `npm install @blockly/continuous-toolbox@7.0.9`

Import its three plugin classes and pass them through Blockly's `plugins` injection option. Preserve the existing toolbox search item if compatible; if the plugin cannot render that toolbox item, keep search as a separate styled control backed by the existing search plugin.

- [ ] **Step 4: Add category color markers and continuous flyout styling**

Use schema category styles/colors, not hardcoded block-type maps. Style the category rail with color dots, section labels, a restrained selected state, and responsive flyout width.

- [ ] **Step 5: Run focused tests and verify GREEN**

Run: `npm test -- src/tests/continuousToolbox.test.ts src/tests/toolboxStyle.test.ts`

Expected: all continuous toolbox tests pass.

### Task 4: Regression and export verification

**Files:**
- Modify: `src/tests/App.test.tsx` only if integration assertions require correction
- Modify: `playwright.config.ts` or existing Playwright spec only if the current harness requires the new labels

**Interfaces:**
- The UI outputs the same `LessonAst` consumed by `astToTutorialBundle`.
- Existing exporter and syntax parity interfaces remain unchanged.

- [ ] **Step 1: Run all unit tests**

Run: `npm test`

Expected: complete Vitest suite passes.

- [ ] **Step 2: Build the production application**

Run: `npm run build`

Expected: TypeScript and Vite build complete without errors.

- [ ] **Step 3: Run syntax parity**

Run: `npm run test:syntax-parity`

Expected: all generated YAML cases match the Godot compiler fixtures.

- [ ] **Step 4: Run Playwright smoke coverage**

Run: `npm run e2e`

Expected: workspace creation, category navigation, panel collapse, and ZIP export smoke paths pass.

- [ ] **Step 5: Review the final diff**

Run: `git diff --check` and `git status --short`.

Expected: no whitespace errors or generated files outside the intended dependency lockfile/build inputs.
