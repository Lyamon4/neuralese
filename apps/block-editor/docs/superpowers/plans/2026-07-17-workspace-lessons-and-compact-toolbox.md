# Workspace Lessons and Compact Toolbox Implementation Plan

**Goal:** Add lessons inside workspaces, remove Blockly search completely, and reduce the category rail width while preserving the existing Neuralese bundle format.

**Architecture:** React owns a nested `WorkspaceDraft[]` editor model. The YAML/export boundary remains unchanged by flattening every workspace's lessons into the existing `LessonAst.lessons` array. Blockly continues to derive categories and block definitions from the JSON schema; only the search toolbox item and dependency are removed.

**Tech Stack:** React 19, TypeScript 5.7, Blockly 12, Vitest, Testing Library, Playwright, JSZip.

## Global Constraints

- Workspaces are editor-only containers and are not serialized into YAML.
- Exports remain `bundle.yaml` plus `lessons/<key>.yaml`.
- Lesson keys are generated from lesson names and remain unique across the entire bundle.
- Every workspace contains at least one lesson, and every bundle contains at least one workspace.
- Search is removed from the toolbox, source imports, dependency manifest, lockfile, and styles.
- Block types, category order, colors, and YAML mappings remain schema-driven.

### Task 1: Nested workspace model

**Files:**
- Modify: `src/core/lessonDrafts.ts`
- Modify: `src/tests/lessonDrafts.test.ts`

- [x] Add failing tests for creating an initial workspace, flattening its lessons, and generating globally unique lesson keys.
- [x] Run `npm test -- src/tests/lessonDrafts.test.ts` and confirm the new tests fail because the workspace helpers are absent.
- [x] Add `WorkspaceDraft`, `createWorkspaceDraft`, `createInitialWorkspaceDraft`, and `workspaceLessons`.
- [x] Run the focused tests and confirm they pass.

### Task 2: Lessons inside workspaces

**Files:**
- Modify: `src/app/App.tsx`
- Replace: `src/app/WorkspaceDialog.tsx` with `src/app/NamingDialog.tsx`
- Modify: `src/app/App.css`
- Modify: `src/tests/App.test.tsx`

- [x] Add failing tests for creating, selecting, and deleting lessons inside the selected workspace.
- [x] Run `npm test -- src/tests/App.test.tsx` and confirm the new tests fail for the missing lesson controls.
- [x] Store nested workspaces in `App`, flatten lessons only when constructing `LessonAst`, and update Blockly changes inside the selected lesson.
- [x] Add separate workspace and lesson naming dialogs, nested lesson rows, and one-item deletion guards.
- [x] Run the focused App tests and confirm they pass.

### Task 3: Remove search and compact the toolbox

**Files:**
- Modify: `package.json`
- Modify: `package-lock.json`
- Modify: `src/blockly/BlocklyWorkspace.tsx`
- Modify: `src/blockly/createToolbox.ts`
- Modify: `src/app/App.css`
- Modify: `src/tests/continuousToolbox.test.ts`
- Modify: `src/tests/toolboxStyle.test.ts`

- [x] Add failing contracts proving the toolbox has no search item/import/dependency and uses an `88px` category rail.
- [x] Run the focused toolbox tests and confirm the contracts fail against the current search implementation.
- [x] Remove the search item, import, package, and search-only CSS, then reduce category marker and label dimensions.
- [x] Run the focused tests and confirm they pass.

### Task 4: Integration verification

**Files:**
- Modify: `e2e/exportBundle.spec.ts`

- [x] Extend Playwright coverage to create a lesson inside a workspace and verify both lesson YAML files in the ZIP.
- [x] Run `npm test`, `npm run build`, `npm run e2e`, `npm run test:syntax-parity`, and `git diff --check`.
- [x] Run `git status --short` and confirm only the intended files are ready for commit.
