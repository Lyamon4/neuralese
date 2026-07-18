import * as Blockly from "blockly";

const shortcutRegistrars = [
  [Blockly.ShortcutItems.names.UNDO, Blockly.ShortcutItems.registerUndo],
  [Blockly.ShortcutItems.names.REDO, Blockly.ShortcutItems.registerRedo],
  [Blockly.ShortcutItems.names.DELETE, Blockly.ShortcutItems.registerDelete],
] as const;

export function registerBlocklyEditorShortcuts(): void {
  const registry = Blockly.ShortcutRegistry.registry;

  for (const [name, register] of shortcutRegistrars) {
    if (!registry.getRegistry()[name]) {
      register();
    }
  }
}
