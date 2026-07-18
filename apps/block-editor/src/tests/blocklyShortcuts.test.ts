import * as Blockly from "blockly";
import { describe, expect, it } from "vitest";
import { registerBlocklyEditorShortcuts } from "../blockly/registerBlocklyShortcuts";

describe("Blockly editor shortcuts", () => {
  it("registers undo, redo, and delete idempotently", () => {
    const registry = Blockly.ShortcutRegistry.registry;
    registry.reset();

    try {
      registerBlocklyEditorShortcuts();
      registerBlocklyEditorShortcuts();

      expect(registry.getRegistry()[Blockly.ShortcutItems.names.UNDO]).toBeTruthy();
      expect(registry.getRegistry()[Blockly.ShortcutItems.names.REDO]).toBeTruthy();
      expect(registry.getRegistry()[Blockly.ShortcutItems.names.DELETE]).toBeTruthy();
    } finally {
      registry.reset();
      Blockly.ShortcutItems.registerDefaultShortcuts();
    }
  });
});
