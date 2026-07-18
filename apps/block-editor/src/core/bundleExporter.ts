import JSZip from "jszip";
import YAML from "yaml";
import type { TutorialBundle, TutorialLesson } from "./bundleModel";
import { validateBundle } from "./bundleValidator";

export function buildBundleFiles(bundle: TutorialBundle): Record<string, string> {
  const validation = validateBundle(bundle);
  if (!validation.ok) {
    throw new Error(validation.errors.join("\n"));
  }

  const files: Record<string, string> = {
    "bundle.yaml": YAML.stringify({
      name: bundle.name,
      lesson_order: bundle.lessons.map((lesson) => lesson.key),
    }),
  };

  for (const lesson of bundle.lessons) {
    files[`lessons/${lesson.key}.yaml`] = YAML.stringify(lessonToYamlObject(lesson));
  }

  return files;
}

export async function exportBundleZip(bundle: TutorialBundle): Promise<Blob> {
  const zip = new JSZip();
  const files = buildBundleFiles(bundle);

  for (const [path, content] of Object.entries(files)) {
    zip.file(path, content);
  }

  return zip.generateAsync({
    type: "blob",
    compression: "DEFLATE",
    platform: "UNIX",
  });
}

export async function exportBundleZipBytes(bundle: TutorialBundle): Promise<Uint8Array> {
  const zip = new JSZip();
  const files = buildBundleFiles(bundle);

  for (const [path, content] of Object.entries(files)) {
    zip.file(path, content);
  }

  return zip.generateAsync({
    type: "uint8array",
    compression: "DEFLATE",
    platform: "UNIX",
  });
}

function lessonToYamlObject(lesson: TutorialLesson): Record<string, unknown> {
  const out: Record<string, unknown> = {
    lesson_title: lesson.title,
    flow: lesson.flow,
  };
  if (lesson.branches && Object.keys(lesson.branches).length > 0) {
    out.branches = lesson.branches;
  }
  if (lesson.autoProject) {
    out.auto_project = lesson.autoProject;
  }
  if (lesson.autoProjectName) {
    out.auto_project_name = lesson.autoProjectName;
  }
  return out;
}
