import { describe, expect, it } from "vitest";
import {
  createInitialWorkspaceDraft,
  createLessonDraft,
  createLessonKey,
  createNamedLessonKey,
  createWorkspaceDraft,
  lessonKeyFromName,
  workspaceLessons,
} from "../core/lessonDrafts";

describe("lesson drafts", () => {
  it("creates a new lesson with a unique key and root workspace", () => {
    const first = createInitialWorkspaceDraft().lessons[0];
    const key = createLessonKey([first], "lesson");
    const second = createLessonDraft(key, "Lesson 2");

    expect(key).toBe("lesson");
    expect(second.key).toBe("lesson");
    expect(second.workspaceXml).toContain('type="lesson_root"');
    expect(second.workspaceXml).toContain("<next>");
    expect(second.workspaceXml).not.toContain('<statement name="flow">');
  });

  it("increments duplicate lesson keys", () => {
    const first = createLessonDraft("lesson", "Lesson");
    const second = createLessonDraft("lesson_2", "Lesson 2");

    expect(createLessonKey([first, second], "lesson")).toBe("lesson_3");
  });

  it("creates an initial workspace with one selected lesson", () => {
    const workspace = createInitialWorkspaceDraft();

    expect(workspace.name).toBe("Intro workspace");
    expect(workspace.lessons).toHaveLength(1);
    expect(workspace.lessons[0].title).toBe("Intro lesson");
    expect(workspace.lessons[0].key).toBe("intro_lesson");
    expect(workspace.activeLessonId).toBe(workspace.lessons[0].id);
  });

  it("flattens lessons from every workspace for bundle export", () => {
    const first = createWorkspaceDraft("First", [
      createLessonDraft("first_lesson", "First lesson"),
    ]);
    const second = createWorkspaceDraft("Second", [
      createLessonDraft("second_lesson", "Second lesson"),
      createLessonDraft("third_lesson", "Third lesson"),
    ]);

    expect(workspaceLessons([first, second]).map((lesson) => lesson.key)).toEqual([
      "first_lesson",
      "second_lesson",
      "third_lesson",
    ]);
  });

  it("generates a stable lesson key from its visible name", () => {
    expect(lessonKeyFromName("  My First Lesson!  ")).toBe("my_first_lesson");
    expect(lessonKeyFromName("---")).toBe("lesson");
  });

  it("makes generated lesson keys unique across workspaces", () => {
    const first = createLessonDraft("image_classifier", "Image classifier");
    const second = createLessonDraft("image_classifier_2", "Image classifier");

    expect(createNamedLessonKey([first, second], "Image classifier")).toBe(
      "image_classifier_3",
    );
  });
});
