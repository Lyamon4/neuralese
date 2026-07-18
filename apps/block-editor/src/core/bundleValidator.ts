import type { TutorialBundle } from "./bundleModel";

export type ValidationResult = {
  ok: boolean;
  errors: string[];
};

export function validateBundle(bundle: TutorialBundle): ValidationResult {
  const errors: string[] = [];
  if (!bundle.name.trim()) errors.push("Bundle name is required.");
  if (bundle.lessons.length === 0) errors.push("Add at least one lesson.");

  const seen = new Set<string>();
  for (const lesson of bundle.lessons) {
    if (!lesson.key.trim()) errors.push("Every lesson needs an internal key.");
    if (seen.has(lesson.key)) errors.push(`Duplicate lesson key: ${lesson.key}`);
    seen.add(lesson.key);
    if (!lesson.title.trim()) errors.push(`Lesson '${lesson.key}' needs a title.`);
    if (lesson.flow.length === 0) errors.push(`Lesson '${lesson.key}' needs at least one step.`);
    const branchNames = new Set(Object.keys(lesson.branches ?? {}));
    if (branchNames.has("flow")) {
      errors.push("Branch name 'flow' is reserved.");
    }
    for (const [name, steps] of Object.entries(lesson.branches ?? {})) {
      if (!name.trim()) errors.push("Branch names cannot be empty.");
      if (!Array.isArray(steps) || steps.length === 0) {
        errors.push(`Branch '${name}' needs at least one step.`);
      }
    }
    const gotoTargets = collectGotoTargets([lesson.flow, lesson.branches ?? {}]);
    for (const target of gotoTargets) {
      if (!branchNames.has(target)) {
        errors.push(`Goto references unknown branch '${target}'.`);
      }
    }
    if (lesson.autoProject?.includes("..") || lesson.autoProject?.includes("://")) {
      errors.push(`Lesson '${lesson.key}' auto project must be a safe relative .scn path.`);
    }
  }

  return { ok: errors.length === 0, errors };
}

function collectGotoTargets(value: unknown, targets = new Set<string>()): Set<string> {
  if (Array.isArray(value)) {
    value.forEach((item) => collectGotoTargets(item, targets));
    return targets;
  }
  if (!value || typeof value !== "object") return targets;

  const record = value as Record<string, unknown>;
  if (
    Object.keys(record).length === 1 &&
    typeof record.goto === "string" &&
    record.goto.trim()
  ) {
    targets.add(record.goto.trim());
    return targets;
  }
  Object.values(record).forEach((item) => collectGotoTargets(item, targets));
  return targets;
}
