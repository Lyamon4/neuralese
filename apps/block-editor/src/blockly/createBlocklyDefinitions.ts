import * as Blockly from "blockly";
import type {
  LoadedTutorialSchema,
  TutorialBlockSchema,
} from "../core/schemaTypes";
import { categoryToBlockStyle } from "./tutorialTheme";

export type BlocklyJsonDefinition = {
  type: string;
  message0: string;
  args0?: unknown[];
  previousStatement?: null | string | string[];
  nextStatement?: null | string | string[];
  output?: string | string[] | null;
  colour?: number | string;
  style?: string;
  tooltip?: string;
  helpUrl: string;
  extensions?: string[];
};

const DYNAMIC_CONTENT_EXTENSION = "tutorial_dynamic_content";
const NEURALESE_CHECKBOX_FIELD = "field_neuralese_checkbox";
const NEURALESE_DROPDOWN_FIELD = "field_neuralese_dropdown";
const NEURALESE_OPTION_LIST_FIELD = "field_neuralese_option_list";
let neuraleseCheckboxFieldRegistered = false;
let neuraleseDropdownFieldRegistered = false;
let neuraleseOptionListFieldRegistered = false;

type DynamicVisibilityRule = {
  targetField: string;
  controllerField: string;
  equals?: unknown;
  notEmpty?: boolean;
};

const dynamicVisibilityRulesByBlockType = new Map<string, DynamicVisibilityRule[]>();
let dynamicContentExtensionRegistered = false;

export function createBlocklyDefinitions(
  loaded: LoadedTutorialSchema,
): BlocklyJsonDefinition[] {
  return [...loaded.blocksByType.values()].map(blockToBlocklyJson);
}

function blockToBlocklyJson(block: TutorialBlockSchema): BlocklyJsonDefinition {
  ensureNeuraleseCheckboxFieldRegistered();
  ensureNeuraleseDropdownFieldRegistered();
  ensureNeuraleseOptionListFieldRegistered();
  const dynamicRules = createDynamicVisibilityRules(block);
  if (dynamicRules.length > 0) {
    dynamicVisibilityRulesByBlockType.set(block.type, dynamicRules);
    ensureDynamicContentExtensionRegistered();
  } else {
    dynamicVisibilityRulesByBlockType.delete(block.type);
  }

  const fieldArgs = block.fields.map((field) => {
    const arg: Record<string, unknown> = {
      type: fieldToBlocklyFieldType(field.type),
      name: field.name,
    };
    if (field.type === "label") {
      arg.text = String(field.default ?? field.label ?? "");
    } else if (field.type === "number") {
      arg.value = Number(field.default ?? 0);
      arg.min = field.min;
      arg.max = field.max;
      arg.precision = field.precision;
    } else if (field.type === "bool") {
      arg.checked = Boolean(field.default);
    } else if (
      field.type === "select" ||
      field.type === "wait_mode" ||
      field.type === "node_type" ||
      field.type === "event_name" ||
      field.type === "branch_ref"
    ) {
      arg.options =
        field.type === "branch_ref"
          ? [[field.required ? "Create a branch first" : "No branch", ""]]
          : field.options?.map((option) => [option.label, option.value]);
    } else {
      arg.text = String(field.default ?? "");
      arg.spellcheck = field.type === "textarea" || field.type === "text";
    }
    return arg;
  });
  const statementArgs = (block.statementInputs ?? []).map((input) => ({
    type: "input_statement",
    name: input.name,
    check: input.check,
  }));
  const args0 = [...fieldArgs, ...statementArgs];

  const definition: BlocklyJsonDefinition = {
    type: block.type,
    message0: withMissingPlaceholders(block.message, block.fields.length, block.statementInputs ?? []),
    args0,
    style: categoryToBlockStyle(block.category, block.kind === "hat"),
    tooltip: block.tooltip ?? "",
    helpUrl: "",
    extensions: dynamicRules.length > 0 ? [DYNAMIC_CONTENT_EXTENSION] : undefined,
  };

  if (block.connection?.previous !== undefined) {
    definition.previousStatement = block.connection.previous;
  }
  if (block.connection?.next !== undefined) {
    definition.nextStatement = block.connection.next;
  }
  if (block.connection?.output !== undefined) {
    definition.output = block.connection.output;
  }

  return definition;
}

function fieldToBlocklyFieldType(type: string): string {
  if (type === "label") return "field_label";
  if (type === "bool") return NEURALESE_CHECKBOX_FIELD;
  if (type === "option_list") return NEURALESE_OPTION_LIST_FIELD;
  if (
    type === "select" ||
    type === "wait_mode" ||
    type === "node_type" ||
    type === "event_name" ||
    type === "branch_ref"
  ) {
    return NEURALESE_DROPDOWN_FIELD;
  }
  if (type === "number") return "field_number";
  return "field_input";
}

export function recolorBlocklyDropdownArrow(
  dataUri: string,
  colour: string,
): string {
  const marker = "base64,";
  const markerIndex = dataUri.indexOf(marker);
  if (markerIndex < 0 || !colour.trim()) return dataUri;
  const prefix = dataUri.slice(0, markerIndex + marker.length);
  const svg = globalThis.atob(dataUri.slice(markerIndex + marker.length));
  return `${prefix}${globalThis.btoa(svg.replace(/#fff\b/gi, colour.trim()))}`;
}

class NeuraleseDropdownField extends Blockly.FieldDropdown {
  static override fromJson(options: Blockly.FieldDropdownFromJsonConfig) {
    return new NeuraleseDropdownField(options.options ?? [["", ""]], undefined, options);
  }

  override initView(): void {
    super.initView();
    this.updateArrowColour();
  }

  override applyColour(): void {
    super.applyColour();
    this.updateArrowColour();
  }

  private updateArrowColour(): void {
    const arrow = (
      this as unknown as { svgArrow?: SVGImageElement | null }
    ).svgArrow;
    if (!arrow) return;
    const colour = getComputedStyle(document.documentElement)
      .getPropertyValue("--dropdown-arrow-color")
      .trim();
    const constants = this.getConstants();
    if (!constants) return;
    const builtInArrow = constants.FIELD_DROPDOWN_SVG_ARROW_DATAURI;
    const recolored = recolorBlocklyDropdownArrow(builtInArrow, colour);
    arrow.setAttribute("href", recolored);
    arrow.setAttributeNS("http://www.w3.org/1999/xlink", "href", recolored);
  }
}

class NeuraleseOptionListField extends Blockly.FieldTextInput {
  private editorInitialValue = "";

  static override fromJson(options: Blockly.FieldTextInputFromJsonConfig) {
    return new NeuraleseOptionListField(options.text, undefined, options);
  }

  protected override getDisplayText_(): string {
    const count = String(this.getValue() ?? "")
      .split(/\r?\n/)
      .map((option) => option.trim())
      .filter(Boolean).length;
    return `${count} ${count === 1 ? "option" : "options"}`;
  }

  protected override widgetCreate_(): HTMLTextAreaElement {
    const input = super.widgetCreate_() as HTMLInputElement;
    this.unbindInputEvents_();
    this.editorInitialValue = String(this.getValue() ?? "");

    const textarea = document.createElement("textarea");
    for (const attribute of input.getAttributeNames()) {
      const value = input.getAttribute(attribute);
      if (value !== null) textarea.setAttribute(attribute, value);
    }
    textarea.classList.add("blocklyOptionListEditor");
    textarea.style.cssText = input.style.cssText;
    textarea.value = this.editorInitialValue;
    textarea.defaultValue = this.editorInitialValue;

    const panel = document.createElement("div");
    panel.className = "blocklyOptionListPanel";
    const title = document.createElement("div");
    title.className = "blocklyOptionListTitle";
    title.textContent = "Options";
    const actions = document.createElement("div");
    actions.className = "blocklyOptionListActions";
    const editorBody = document.createElement("div");
    editorBody.className = "blocklyOptionListEditorBody";
    const bullets = document.createElement("div");
    bullets.className = "blocklyOptionListBullets";
    bullets.setAttribute("aria-hidden", "true");
    const addButton = this.createEditorButton("Add option", "add");
    const cancelButton = this.createEditorButton("Cancel", "cancel");
    const applyButton = this.createEditorButton("Apply", "apply");

    const syncBullets = () => {
      const lineCount = Math.max(1, textarea.value.split(/\r?\n/).length);
      bullets.replaceChildren(
        ...Array.from({ length: lineCount }, () => {
          const bullet = document.createElement("span");
          bullet.textContent = "\u2022";
          return bullet;
        }),
      );
    };
    textarea.addEventListener("input", syncBullets);
    textarea.addEventListener("scroll", () => {
      bullets.style.transform = `translateY(${-textarea.scrollTop}px)`;
    });
    textarea.addEventListener("beforeinput", (event) => {
      if (
        event.inputType === "insertLineBreak" ||
        event.inputType === "insertParagraph"
      ) {
        event.preventDefault();
      }
    });
    textarea.addEventListener("paste", (event) => {
      const pasted = event.clipboardData?.getData("text");
      if (!pasted || !/[\r\n]/.test(pasted)) return;
      event.preventDefault();
      const normalized = pasted.replace(/\s*[\r\n]+\s*/g, " ");
      textarea.setRangeText(
        normalized,
        textarea.selectionStart,
        textarea.selectionEnd,
        "end",
      );
      textarea.dispatchEvent(new Event("input", { bubbles: true }));
    });
    addButton.addEventListener("click", () => {
      const separator = textarea.value && !textarea.value.endsWith("\n") ? "\n" : "";
      textarea.value += separator;
      textarea.dispatchEvent(new Event("input", { bubbles: true }));
      textarea.focus();
      textarea.setSelectionRange(textarea.value.length, textarea.value.length);
    });
    cancelButton.addEventListener("click", () => this.closeEditor(false));
    applyButton.addEventListener("click", () => this.closeEditor(true));

    actions.append(addButton, cancelButton, applyButton);
    editorBody.append(bullets, textarea);
    panel.append(title, editorBody, actions);
    input.replaceWith(panel);
    syncBullets();

    this.htmlInput_ = textarea as unknown as HTMLInputElement;
    this.bindInputEvents_(textarea);
    this.resizeEditor_();
    return textarea;
  }

  protected override resizeEditor_(): void {
    if (!(this.htmlInput_ instanceof HTMLTextAreaElement)) {
      super.resizeEditor_();
      return;
    }
    this.htmlInput_.style.width = "320px";
    this.htmlInput_.style.height = "156px";
  }

  protected override onHtmlInputKeyDown_(event: KeyboardEvent): void {
    if (event.key === "Escape") {
      event.preventDefault();
      event.stopPropagation();
      this.closeEditor(false);
      return;
    }
    if (event.key === "Enter" && (event.ctrlKey || event.metaKey)) {
      event.preventDefault();
      event.stopPropagation();
      this.closeEditor(true);
      return;
    }
    if (event.key === "Enter") {
      event.preventDefault();
      event.stopPropagation();
      return;
    }
    super.onHtmlInputKeyDown_(event);
  }

  private createEditorButton(
    label: string,
    action: "add" | "cancel" | "apply",
  ): HTMLButtonElement {
    const button = document.createElement("button");
    button.type = "button";
    button.className = `blocklyOptionListButton ${action}`;
    button.textContent = label;
    button.addEventListener("pointerdown", (event) => event.stopPropagation());
    return button;
  }

  private closeEditor(apply: boolean): void {
    if (!apply) {
      this.setEditorValue_(this.editorInitialValue);
    }
    Blockly.WidgetDiv.hide();
  }
}

class NeuraleseCheckboxField extends Blockly.FieldCheckbox {
  private static readonly SIDE = 28;

  static override fromJson(options: Blockly.FieldCheckboxFromJsonConfig) {
    return new NeuraleseCheckboxField(options.checked, undefined, options);
  }

  override initView(): void {
    super.initView();
    this.getTextElement().style.display = "block";
    this.getTextElement().textContent = this.getDisplayText_();
    this.centerTextElement();
  }

  override getDisplayText_(): string {
    return this.getValueBoolean() ? "✓" : "×";
  }

  override render_(): void {
    super.render_();
    this.size_ = new Blockly.utils.Size(
      NeuraleseCheckboxField.SIDE,
      NeuraleseCheckboxField.SIDE,
    );
    this.borderRect_?.setAttribute("width", String(NeuraleseCheckboxField.SIDE));
    this.borderRect_?.setAttribute("height", String(NeuraleseCheckboxField.SIDE));
    this.borderRect_?.setAttribute("rx", String(NeuraleseCheckboxField.SIDE / 2));
    this.borderRect_?.setAttribute("ry", String(NeuraleseCheckboxField.SIDE / 2));
    this.centerTextElement();
  }

  protected override doValueUpdate_(newValue: "TRUE" | "FALSE"): void {
    super.doValueUpdate_(newValue);
    if (this.textElement_) {
      this.textElement_.style.display = "block";
      this.textElement_.textContent = this.getDisplayText_();
      this.centerTextElement();
    }
  }

  private centerTextElement(): void {
    if (!this.textElement_) return;
    this.textElement_.style.display = "block";
    this.textElement_.setAttribute("x", String(NeuraleseCheckboxField.SIDE / 2));
    this.textElement_.setAttribute("y", String(NeuraleseCheckboxField.SIDE / 2));
    this.textElement_.setAttribute("text-anchor", "middle");
    this.textElement_.setAttribute("dominant-baseline", "central");
  }
}

function ensureNeuraleseDropdownFieldRegistered(): void {
  if (neuraleseDropdownFieldRegistered) return;
  Blockly.fieldRegistry.register(
    NEURALESE_DROPDOWN_FIELD,
    NeuraleseDropdownField,
  );
  neuraleseDropdownFieldRegistered = true;
}

function ensureNeuraleseOptionListFieldRegistered(): void {
  if (neuraleseOptionListFieldRegistered) return;
  Blockly.fieldRegistry.register(
    NEURALESE_OPTION_LIST_FIELD,
    NeuraleseOptionListField,
  );
  neuraleseOptionListFieldRegistered = true;
}

function ensureNeuraleseCheckboxFieldRegistered(): void {
  if (neuraleseCheckboxFieldRegistered) return;
  Blockly.fieldRegistry.register(NEURALESE_CHECKBOX_FIELD, NeuraleseCheckboxField);
  neuraleseCheckboxFieldRegistered = true;
}

function createDynamicVisibilityRules(
  block: TutorialBlockSchema,
): DynamicVisibilityRule[] {
  return block.fields
    .filter((field) => field.visibleWhen)
    .map((field) => ({
      targetField: field.name,
      controllerField: field.visibleWhen?.field ?? "",
      equals: field.visibleWhen?.equals,
      notEmpty: field.visibleWhen?.notEmpty,
    }))
    .filter((rule) => rule.targetField && rule.controllerField);
}

function ensureDynamicContentExtensionRegistered(): void {
  if (dynamicContentExtensionRegistered) return;
  if (Blockly.Extensions.isRegistered(DYNAMIC_CONTENT_EXTENSION)) {
    dynamicContentExtensionRegistered = true;
    return;
  }

  Blockly.Extensions.register(DYNAMIC_CONTENT_EXTENSION, function dynamicContentExtension() {
    const block = this as Blockly.BlockSvg;
    const updateVisibility = () => {
      applyDynamicVisibility(block);
    };
    const existingOnChange = block.onchange?.bind(block);
    block.setOnChange((event) => {
      existingOnChange?.(event);
      updateVisibility();
    });
    queueMicrotask(updateVisibility);
  });
  dynamicContentExtensionRegistered = true;
}

function applyDynamicVisibility(block: Blockly.BlockSvg): void {
  const rules = dynamicVisibilityRulesByBlockType.get(block.type) ?? [];
  let changed = false;

  for (const rule of rules) {
    const target = block.getField(rule.targetField);
    if (!target) continue;
    const visible = dynamicVisibilityMatches(block, rule);
    if (target.isVisible() === visible) continue;
    target.setVisible(visible);
    changed = true;
  }

  if (changed && block.rendered) {
    block.render();
  }
}

function dynamicVisibilityMatches(
  block: Blockly.Block,
  rule: DynamicVisibilityRule,
): boolean {
  const value = block.getFieldValue(rule.controllerField);
  if (rule.notEmpty) {
    return value != null && String(value).trim() !== "";
  }
  return value === rule.equals;
}

function withMissingPlaceholders(
  message: string,
  fieldCount: number,
  statementInputs: Array<{ label: string }>,
): string {
  let result = message;
  let placeholderCount = countPlaceholders(message);
  for (let index = placeholderCount; index < fieldCount; index += 1) {
    result += ` %${index + 1}`;
  }
  placeholderCount = countPlaceholders(result);
  for (const input of statementInputs) {
    placeholderCount += 1;
    result += `\n${input.label} %${placeholderCount}`;
  }
  return result;
}

function countPlaceholders(message: string): number {
  return message.match(/%\d+/g)?.length ?? 0;
}
