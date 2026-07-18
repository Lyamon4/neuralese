import type { LessonAst } from "./lessonAst";
import type { LoadedTutorialSchema } from "./schemaTypes";
import { emitWorkspaceBlocksToYamlData } from "./yamlEmitter";

export type TutorialLesson = {
  key: string;
  title: string;
  flow: unknown[];
  branches?: Record<string, unknown[]>;
  autoProject?: string;
  autoProjectName?: string;
};

export type TutorialBundle = {
  name: string;
  lessons: TutorialLesson[];
};

export function astToTutorialBundle(
  ast: LessonAst,
  loaded: LoadedTutorialSchema,
): TutorialBundle {
  return {
    name: ast.bundleName,
    lessons: ast.lessons.map((lesson) => {
      const mainRoots = lesson.blocks.filter(
        (block) => loaded.blocksByType.get(block.type)?.role === "lesson_root",
      );
      if (mainRoots.length !== 1) {
        throw new Error(`Lesson '${lesson.key}' must contain exactly one main root`);
      }
      const mainData = emitWorkspaceBlocksToYamlData(
        mainRoots,
        loaded.emitRulesByType,
      )[0];
      if (!isRecord(mainData) || !Array.isArray(mainData.flow)) {
        throw new Error(`Lesson '${lesson.key}' main root did not emit a flow array`);
      }

      const branches: Record<string, unknown[]> = {};
      const branchRoots = lesson.blocks.filter(
        (block) => loaded.blocksByType.get(block.type)?.role === "lesson_branch",
      );
      for (const emitted of emitWorkspaceBlocksToYamlData(
        branchRoots,
        loaded.emitRulesByType,
      )) {
        if (!isRecord(emitted) || Object.keys(emitted).length !== 1) {
          throw new Error(`Lesson '${lesson.key}' branch root must emit one named branch`);
        }
        const [name] = Object.keys(emitted);
        const steps = emitted[name];
        if (!name.trim() || !Array.isArray(steps)) {
          throw new Error(`Lesson '${lesson.key}' branch root emitted invalid data`);
        }
        if (name === "flow") {
          throw new Error(`Lesson '${lesson.key}' branch name 'flow' is reserved`);
        }
        if (branches[name]) {
          throw new Error(`Lesson '${lesson.key}' branch '${name}' is duplicated`);
        }
        branches[name] = steps;
      }

      return {
        key: lesson.key,
        title: lesson.title,
        flow: mainData.flow,
        branches: Object.keys(branches).length > 0 ? branches : undefined,
      };
    }),
  };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return !!value && typeof value === "object" && !Array.isArray(value);
}
