import * as Blockly from "blockly";
import themeData from "../theme/editorThemes.json";

export type TutorialThemeMode = keyof typeof themeData;
type RawBlockStyle = readonly [string, string, string, string?];
type TutorialBlockStyle = {
  colourPrimary: string;
  colourSecondary: string;
  colourTertiary: string;
  hat?: string;
};

export const tutorialRendererOverrides = {
  CORNER_RADIUS: 9,
  FIELD_BORDER_RECT_RADIUS: 6,
};

function normalizeBlockStyles(
  styles: Record<string, RawBlockStyle>,
): Record<string, TutorialBlockStyle> {
  return Object.fromEntries(
    Object.entries(styles).map(([name, [primary, secondary, tertiary, hat]]) => [
      name,
      {
        colourPrimary: primary,
        colourSecondary: secondary,
        colourTertiary: tertiary,
        ...(hat ? { hat } : {}),
      },
    ]),
  );
}

export const tutorialBlockStyles = normalizeBlockStyles(
  themeData.dark.blockStyles as unknown as Record<string, RawBlockStyle>,
);
export const tutorialLightBlockStyles = normalizeBlockStyles(
  themeData.light.blockStyles as unknown as Record<string, RawBlockStyle>,
);

const blockStylesByMode: Record<
  TutorialThemeMode,
  Record<string, TutorialBlockStyle>
> = {
  dark: tutorialBlockStyles,
  light: tutorialLightBlockStyles,
};

function createTutorialTheme(mode: TutorialThemeMode): Blockly.Theme {
  const components = themeData[mode].components;
  return Blockly.Theme.defineTheme(`tutorialTheme_${mode}`, {
    name: `tutorialTheme_${mode}`,
    base: Blockly.Themes.Zelos,
    blockStyles: blockStylesByMode[mode],
    fontStyle: {
      family: "'JetBrains Mono Variable', 'JetBrains Mono', ui-monospace, monospace",
      weight: "600",
      size: 12,
    },
    componentStyles: {
      ...components,
      flyoutOpacity: 1,
      insertionMarkerOpacity: 0.5,
      selectedGlowOpacity: 0,
      replacementGlowOpacity: 0,
    },
  });
}

export const tutorialThemes: Record<TutorialThemeMode, Blockly.Theme> = {
  dark: createTutorialTheme("dark"),
  light: createTutorialTheme("light"),
};

export const tutorialThemeCssVariables: Record<
  TutorialThemeMode,
  Record<string, string>
> = {
  dark: themeData.dark.css,
  light: themeData.light.css,
};

export function categoryToBlockStyle(category: string, hat = false): string {
  switch (category) {
    case "Lesson":
      return hat ? "lesson_hat_blocks" : "lesson_blocks";
    case "Teacher":
      return "teacher_blocks";
    case "Feedback":
      return "feedback_blocks";
    case "Student Task":
      return "student_blocks";
    case "Checks":
      return "checks_blocks";
    case "Flow":
      return hat ? "flow_hat_blocks" : "flow_blocks";
    default:
      return "default_blocks";
  }
}

export const tutorialTheme = tutorialThemes.dark;
