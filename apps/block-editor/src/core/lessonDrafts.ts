import type { AstBlock } from "./lessonAst";

export const EMPTY_LESSON_XML = `
<xml xmlns="https://developers.google.com/blockly/xml">
  <block type="lesson_root" x="56" y="48">
    <next>
      <block type="lesson_step">
        <field name="id">welcome</field>
        <field name="title">Welcome</field>
        <field name="persistent">FALSE</field>
        <statement name="actions">
          <block type="action_explain">
            <field name="text">Welcome to this Neuralese lesson.</field>
            <field name="wait">next</field>
            <field name="time">1</field>
            <next>
              <block type="action_explain_next" />
            </next>
          </block>
        </statement>
      </block>
    </next>
  </block>
</xml>`;

export type LessonDraft = {
  id: string;
  key: string;
  title: string;
  workspaceXml: string;
  blocks: AstBlock[];
};

export type WorkspaceDraft = {
  id: string;
  name: string;
  lessons: LessonDraft[];
  activeLessonId: string;
};

export function createInitialLessonDraft(): LessonDraft {
  return createLessonDraft("intro_lesson", "Intro lesson");
}

export function createInitialWorkspaceDraft(): WorkspaceDraft {
  return createWorkspaceDraft("Intro workspace", [createInitialLessonDraft()]);
}

export function createWorkspaceDraft(
  name: string,
  lessons: LessonDraft[],
): WorkspaceDraft {
  if (lessons.length === 0) {
    throw new Error("A workspace must contain at least one lesson");
  }

  return {
    id: createId(),
    name,
    lessons,
    activeLessonId: lessons[0].id,
  };
}

export function workspaceLessons(workspaces: WorkspaceDraft[]): LessonDraft[] {
  return workspaces.flatMap((workspace) => workspace.lessons);
}

export function createLessonDraft(key: string, title: string): LessonDraft {
  return {
    id: createId(),
    key,
    title,
    workspaceXml: EMPTY_LESSON_XML,
    blocks: [],
  };
}

export function createLessonKey(
  lessons: Array<Pick<LessonDraft, "key">>,
  base = "lesson",
): string {
  const used = new Set(lessons.map((lesson) => lesson.key));
  if (!used.has(base)) return base;
  let suffix = 2;
  while (used.has(`${base}_${suffix}`)) suffix += 1;
  return `${base}_${suffix}`;
}

export function lessonKeyFromName(name: string): string {
  return (
    name
      .toLowerCase()
      .trim()
      .replace(/[^a-z0-9_ -]/g, "")
      .replace(/[\s-]+/g, "_")
      .replace(/^_+|_+$/g, "") || "lesson"
  );
}

export function createNamedLessonKey(
  drafts: Array<Pick<LessonDraft, "key">>,
  name: string,
): string {
  return createLessonKey(drafts, lessonKeyFromName(name));
}

function createId(): string {
  return globalThis.crypto?.randomUUID?.() ?? `lesson-${Date.now()}-${Math.random()}`;
}
