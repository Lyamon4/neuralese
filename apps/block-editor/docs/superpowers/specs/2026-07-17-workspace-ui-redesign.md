# Workspace UI redesign

## Goal

Replace lesson-oriented editor terminology with a workspace-oriented experience while preserving the existing Neuralese tutorial bundle format exactly. Teachers work with named workspaces; the exported ZIP continues to contain `bundle.yaml` and one `lessons/<key>.yaml` file per workspace.

## Product model

- A bundle contains one or more workspaces, matching the current multi-lesson behavior.
- `LessonDraft` and the YAML lesson format remain internal implementation details.
- Each workspace has a teacher-facing name and an automatically generated key.
- The key is derived from the workspace name with the existing slug rules and is not directly editable.
- Keys must remain unique inside a bundle. Collisions receive a deterministic numeric suffix.
- Renaming a workspace updates its generated key and exported filename.

## Workspace creation and list

- The existing plus button opens a compact creation dialog.
- The dialog contains `Workspace name`, `Cancel`, and `Create`.
- Submission is available through the Create button and Enter; empty names are rejected inline.
- A new workspace is selected immediately after creation.
- The Bundle panel replaces `Lessons` with `Workspaces`.
- Each workspace row shows its name, generated key, and block count.
- The selected workspace has a clear blue selected state.
- Existing deletion behavior is preserved, including the one-workspace minimum.
- Long names truncate cleanly without resizing the panel.

## Panel layout

- Remove the right-hand Lesson panel completely.
- Move `Export files` into the Bundle panel below the workspace list.
- The Bundle panel header owns its collapse button.
- When collapsed, the panel is removed from the layout and Blockly expands into the released space.
- A small fixed edge tab remains at the left edge of the workspace to restore the Bundle panel.
- The top toolbar no longer contains the Bundle visibility button.

## Validation

- Validation issues move out of the removed Lesson panel.
- When issues exist, a compact red warning trigger with a triangle icon appears at the top of the editor.
- The trigger shows the issue count and expands a readable issue list.
- Export remains disabled while validation issues exist.
- A valid bundle keeps the existing quiet Ready state; no permanent empty validation panel is shown.

## Blockly toolbox

- Keep schema-driven categories and block definitions. No block or YAML mapping is hardcoded in UI components.
- Use the maintained `@blockly/continuous-toolbox` plugin to provide Scratch-style category navigation.
- The left rail shows every schema category with its category color and label.
- The flyout displays all categories as one continuous scrollable block catalog with section labels.
- Clicking a category scrolls the flyout directly to that section.
- Scrolling the flyout updates the active category in the rail.
- Preserve search, existing block colors, custom renderer, connection rules, undo, deletion, and workspace invariants.
- Category styling should match Neuralese rather than copying Scratch: compact typography, restrained blue selected state, category color dots, and the existing JetBrains Mono typeface.

## Data flow

1. The creation dialog receives a workspace name.
2. The app derives a unique key and creates the existing internal lesson draft.
3. Blockly edits update the active draft exactly as before.
4. The UI presents drafts as workspaces.
5. Export converts the unchanged lesson AST into the unchanged tutorial bundle format.

## Error handling

- Empty workspace names cannot be submitted.
- Duplicate generated keys are resolved before draft creation.
- Validation warnings never cover the export button or Blockly controls.
- Collapsing or restoring the Bundle panel triggers a Blockly resize without resetting camera position or workspace state.
- Opening and closing the creation dialog does not recreate Blockly.

## Tests

- Unit tests for name-to-key generation, collisions, renaming, and export filenames.
- Component tests for creation, selection, deletion, Bundle collapse/restore, and top validation display.
- Toolbox tests for continuous category registration and schema-derived category contents.
- Existing syntax parity, YAML emitter, workspace invariant, and exporter tests remain unchanged and must pass.
- Playwright smoke coverage for creating two workspaces, navigating toolbox categories, collapsing the Bundle panel, and exporting a compatible ZIP.

## Out of scope

- Changing the YAML DSL or bundle folder names.
- Migrating `LessonDraft` to a new serialized data type.
- Adding cloud persistence, collaboration, or user accounts.
- Rebuilding Blockly category navigation manually when the maintained plugin provides it.
