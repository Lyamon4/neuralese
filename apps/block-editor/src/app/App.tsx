import * as Blockly from "blockly";
import {
  AlertTriangle,
  Check,
  ChevronLeft,
  ChevronRight,
  Download,
  FileArchive,
  Moon,
  Plus,
  Sun,
  Trash2,
} from "lucide-react";
import { useCallback, useLayoutEffect, useMemo, useState } from "react";
import type { ReactNode } from "react";
import { BlocklyWorkspace } from "../blockly/BlocklyWorkspace";
import { createBranchReferenceConfig } from "../blockly/branchReferences";
import { createBlocklyDefinitions } from "../blockly/createBlocklyDefinitions";
import { createToolbox } from "../blockly/createToolbox";
import {
  tutorialThemes,
  tutorialThemeCssVariables,
  type TutorialThemeMode,
} from "../blockly/tutorialTheme";
import { astToTutorialBundle } from "../core/bundleModel";
import { exportBundleZip } from "../core/bundleExporter";
import { downloadBlob } from "../core/download";
import {
  createInitialWorkspaceDraft,
  createLessonDraft,
  createNamedLessonKey,
  createWorkspaceDraft,
  workspaceLessons,
} from "../core/lessonDrafts";
import type { AstBlock, LessonAst } from "../core/lessonAst";
import { loadTutorialSchema } from "../core/schemaLoader";
import { validateLessonAst } from "../core/syntaxGuardrails";
import { workspaceToLessonAst } from "../core/workspaceToAst";
import logoUrl from "../assets/logo.png";
import nodeCatalog from "../schema/tutorialNodeCatalog.json";
import schema from "../schema/tutorialBlocks.schema.json";
import { NamingDialog, type NamingDialogKind } from "./NamingDialog";

export function App() {
  const [themeMode, setThemeMode] = useState<TutorialThemeMode>(readThemeMode);
  const loaded = useMemo(() => loadTutorialSchema(schema, nodeCatalog), []);
  const blockDefinitions = useMemo(() => createBlocklyDefinitions(loaded), [loaded]);
  const toolbox = useMemo(() => createToolbox(loaded), [loaded]);
  const branchReferenceConfig = useMemo(
    () => createBranchReferenceConfig(loaded),
    [loaded],
  );
  const mainRootBlockTypes = useMemo(
    () =>
      [...loaded.blocksByType.values()]
        .filter((block) => block.role === "lesson_root")
        .map((block) => block.type),
    [loaded],
  );
  const serializableRootBlockTypes = useMemo(
    () =>
      [...loaded.blocksByType.values()]
        .filter(
          (block) =>
            block.role === "lesson_root" || block.role === "lesson_branch",
        )
        .map((block) => block.type),
    [loaded],
  );
  const rootStackInputs = useMemo(
    () =>
      new Map(
        [...loaded.blocksByType.values()]
          .filter((block) => block.stackInput)
          .map((block) => [block.type, block.stackInput as string]),
      ),
    [loaded],
  );
  const [bundleName, setBundleName] = useState("Neuralese custom course");
  const [workspaces, setWorkspaces] = useState(() => [
    createInitialWorkspaceDraft(),
  ]);
  const [activeWorkspaceId, setActiveWorkspaceId] = useState(
    () => workspaces[0].id,
  );
  const [exporting, setExporting] = useState(false);
  const [bundlePanelVisible, setBundlePanelVisible] = useState(true);
  const [namingDialog, setNamingDialog] = useState<NamingDialogKind | null>(
    null,
  );
  const [validationOpen, setValidationOpen] = useState(false);

  useLayoutEffect(() => {
    document.documentElement.dataset.theme = themeMode;
    document.documentElement.style.colorScheme = themeMode;
    for (const [property, value] of Object.entries(
      tutorialThemeCssVariables[themeMode],
    )) {
      document.documentElement.style.setProperty(property, value);
    }
    writeThemeMode(themeMode);
  }, [themeMode]);

  const activeWorkspace =
    workspaces.find((workspace) => workspace.id === activeWorkspaceId) ??
    workspaces[0];
  const activeLesson =
    activeWorkspace.lessons.find(
      (lesson) => lesson.id === activeWorkspace.activeLessonId,
    ) ?? activeWorkspace.lessons[0];
  const lessons = useMemo(() => workspaceLessons(workspaces), [workspaces]);
  const ast = useMemo<LessonAst>(
    () => ({
      bundleName,
      lessons: lessons.map((lesson) => ({
        key: lesson.key,
        title: lesson.title,
        blocks: lesson.blocks,
      })),
    }),
    [bundleName, lessons],
  );
  const issues = useMemo(() => validateLessonAst(ast, loaded), [ast, loaded]);
  const lessonBlockCounts = useMemo(
    () =>
      new Map(
        lessons.map((lesson) => [
          lesson.id,
          visibleBlockCount(lesson.blocks, serializableRootBlockTypes),
        ]),
      ),
    [lessons, serializableRootBlockTypes],
  );

  const handleWorkspaceChanged = useCallback(
    (workspace: Blockly.WorkspaceSvg) => {
      const parsed = workspaceToLessonAst(
        workspace,
        {
          bundleName,
          lessonKey: activeLesson.key,
          lessonTitle: activeLesson.title,
        },
        serializableRootBlockTypes,
        rootStackInputs,
      );
      const workspaceXml = Blockly.Xml.domToText(
        Blockly.Xml.workspaceToDom(workspace),
      );

      setWorkspaces((existing) =>
        existing.map((editorWorkspace) =>
          editorWorkspace.id === activeWorkspaceId
            ? {
                ...editorWorkspace,
                lessons: editorWorkspace.lessons.map((lesson) =>
                  lesson.id === activeLesson.id
                    ? {
                        ...lesson,
                        blocks: parsed.lessons[0].blocks,
                        workspaceXml,
                      }
                    : lesson,
                ),
              }
            : editorWorkspace,
        ),
      );
    },
    [
      activeLesson.key,
      activeLesson.title,
      activeLesson.id,
      activeWorkspaceId,
      bundleName,
      rootStackInputs,
      serializableRootBlockTypes,
    ],
  );

  const handleCreateWorkspace = useCallback(
    (name: string) => {
      const title = name.trim();
      if (!title) return;

      const key = createNamedLessonKey(lessons, title);
      const lesson = createLessonDraft(key, title);
      const workspace = createWorkspaceDraft(title, [lesson]);
      setWorkspaces((existing) => [...existing, workspace]);
      setActiveWorkspaceId(workspace.id);
      setNamingDialog(null);
    },
    [lessons],
  );

  const handleCreateLesson = useCallback(
    (name: string) => {
      const title = name.trim();
      if (!title) return;

      const lesson = createLessonDraft(
        createNamedLessonKey(lessons, title),
        title,
      );
      setWorkspaces((existing) =>
        existing.map((workspace) =>
          workspace.id === activeWorkspaceId
            ? {
                ...workspace,
                lessons: [...workspace.lessons, lesson],
                activeLessonId: lesson.id,
              }
            : workspace,
        ),
      );
      setNamingDialog(null);
    },
    [activeWorkspaceId, lessons],
  );

  const handleDeleteWorkspace = useCallback(() => {
    if (workspaces.length <= 1) return;

    const activeIndex = workspaces.findIndex(
      (workspace) => workspace.id === activeWorkspaceId,
    );
    if (activeIndex < 0) return;

    const nextActive = workspaces[activeIndex + 1] ?? workspaces[activeIndex - 1];
    setWorkspaces((existing) =>
      existing.filter((workspace) => workspace.id !== activeWorkspaceId),
    );
    setActiveWorkspaceId(nextActive.id);
  }, [activeWorkspaceId, workspaces]);

  const handleDeleteLesson = useCallback(() => {
    if (activeWorkspace.lessons.length <= 1) return;

    const activeIndex = activeWorkspace.lessons.findIndex(
      (lesson) => lesson.id === activeLesson.id,
    );
    if (activeIndex < 0) return;

    const nextActive =
      activeWorkspace.lessons[activeIndex + 1] ??
      activeWorkspace.lessons[activeIndex - 1];
    setWorkspaces((existing) =>
      existing.map((workspace) =>
        workspace.id === activeWorkspace.id
          ? {
              ...workspace,
              lessons: workspace.lessons.filter(
                (lesson) => lesson.id !== activeLesson.id,
              ),
              activeLessonId: nextActive.id,
            }
          : workspace,
      ),
    );
  }, [activeLesson.id, activeWorkspace]);

  const handleSelectLesson = useCallback(
    (lessonId: string) => {
      setWorkspaces((existing) =>
        existing.map((workspace) =>
          workspace.id === activeWorkspaceId
            ? { ...workspace, activeLessonId: lessonId }
            : workspace,
        ),
      );
    },
    [activeWorkspaceId],
  );

  const handleExport = useCallback(async () => {
    if (issues.length > 0) return;
    setExporting(true);
    try {
      const bundle = astToTutorialBundle(ast, loaded);
      const blob = await exportBundleZip(bundle);
      downloadBlob(blob, `${slugify(bundleName) || "neuralese"}_bundle.zip`);
    } finally {
      setExporting(false);
    }
  }, [ast, bundleName, issues.length, loaded]);

  const blockCount = [...lessonBlockCounts.values()].reduce(
    (sum, count) => sum + count,
    0,
  );
  const canExport = issues.length === 0 && !exporting;
  const issueLabel = `${issues.length} validation ${
    issues.length === 1 ? "issue" : "issues"
  }`;

  return (
    <main className="appShell" data-theme={themeMode}>
      <header className="topbar">
        <div className="brandBlock">
          <div className="brandMark">
            <img src={logoUrl} alt="Neuralese logo" />
          </div>
          <div>
            <h1>Neuralese Tutorial Builder</h1>
            <p>
              {workspaces.length}{" "}
              {workspaces.length === 1 ? "workspace" : "workspaces"}
              {" · "}
              {lessons.length} {lessons.length === 1 ? "lesson" : "lessons"}
              {" · "}
              {blockCount} {blockCount === 1 ? "block" : "blocks"}
            </p>
          </div>
        </div>
        <div className="topbarActions">
          <button
            className="iconButton"
            type="button"
            aria-label={`Use ${themeMode === "dark" ? "light" : "dark"} theme`}
            title={`Use ${themeMode === "dark" ? "light" : "dark"} theme`}
            onClick={() =>
              setThemeMode((current) =>
                current === "dark" ? "light" : "dark",
              )
            }
          >
            {themeMode === "dark" ? <Sun size={17} /> : <Moon size={17} />}
          </button>
          {issues.length > 0 ? (
            <div className="validationControl">
              <button
                className="validationTrigger"
                type="button"
                aria-label={validationOpen ? "Hide validation issues" : `Show ${issueLabel}`}
                aria-expanded={validationOpen}
                onClick={() => setValidationOpen((open) => !open)}
              >
                <AlertTriangle size={16} />
                <span>{issues.length}</span>
              </button>
              {validationOpen ? (
                <div
                  className="validationPopover"
                  role="alert"
                  aria-label="Validation issues"
                >
                  <div className="validationTitle">
                    <AlertTriangle size={16} />
                    <span>Check workspace</span>
                  </div>
                  <ul>
                    {issues.map((issue) => (
                      <li key={`${issue.path}:${issue.message}`}>{issue.message}</li>
                    ))}
                  </ul>
                </div>
              ) : null}
            </div>
          ) : (
            <span className="readyState">
              <Check size={14} />
              Ready
            </span>
          )}
          <button
            className="primaryButton"
            type="button"
            disabled={!canExport}
            onClick={handleExport}
          >
            <Download size={17} />
            {exporting ? "Exporting" : "Export ZIP"}
          </button>
        </div>
      </header>

      <section className={`editorGrid${bundlePanelVisible ? "" : " bundleHidden"}`}>
        {bundlePanelVisible ? (
          <aside className="leftPanel">
            <div className="panelHeader">
              <PanelTitle icon={<FileArchive size={17} />} title="Bundle" />
            </div>
            <Field label="Bundle name" value={bundleName} onChange={setBundleName} />
            <div className="workspaceListHeader">
              <span>Workspaces</span>
              <div className="workspaceListActions">
                <button
                  className="deleteWorkspaceButton"
                  type="button"
                  aria-label="Delete selected workspace"
                  title={
                    workspaces.length <= 1
                      ? "At least one workspace is required"
                      : "Delete selected workspace"
                  }
                  disabled={workspaces.length <= 1}
                  onClick={handleDeleteWorkspace}
                >
                  <Trash2 size={15} />
                </button>
                <button
                  type="button"
                  aria-label="Add workspace"
                  title="Add workspace"
                  onClick={() => setNamingDialog("workspace")}
                >
                  <Plus size={16} />
                </button>
              </div>
            </div>
            <div className="workspaceList">
              {workspaces.map((workspace, index) => {
                const workspaceBlockCount = workspace.lessons.reduce(
                  (sum, lesson) => sum + (lessonBlockCounts.get(lesson.id) ?? 0),
                  0,
                );
                const lessonCount = workspace.lessons.length;
                const displayName = workspace.name || `Workspace ${index + 1}`;
                return (
                  <button
                    className={`workspaceRow${
                      workspace.id === activeWorkspace.id ? " selected" : ""
                    }`}
                    type="button"
                    key={workspace.id}
                    aria-label={`${displayName} ${lessonCount} ${
                      lessonCount === 1 ? "lesson" : "lessons"
                    } ${workspaceBlockCount} ${
                      workspaceBlockCount === 1 ? "block" : "blocks"
                    }`}
                    onClick={() => setActiveWorkspaceId(workspace.id)}
                  >
                    <span>{displayName}</span>
                    <small>
                      {lessonCount} {lessonCount === 1 ? "lesson" : "lessons"}
                    </small>
                    <em>
                      {workspaceBlockCount} {workspaceBlockCount === 1 ? "block" : "blocks"}
                    </em>
                  </button>
                );
              })}
            </div>

            <div className="workspaceListHeader lessonListHeader">
              <span>Lessons</span>
              <div className="workspaceListActions">
                <button
                  className="deleteLessonButton"
                  type="button"
                  aria-label="Delete selected lesson"
                  title={
                    activeWorkspace.lessons.length <= 1
                      ? "At least one lesson is required"
                      : "Delete selected lesson"
                  }
                  disabled={activeWorkspace.lessons.length <= 1}
                  onClick={handleDeleteLesson}
                >
                  <Trash2 size={15} />
                </button>
                <button
                  type="button"
                  aria-label="Add lesson"
                  title="Add lesson"
                  onClick={() => setNamingDialog("lesson")}
                >
                  <Plus size={16} />
                </button>
              </div>
            </div>
            <div className="lessonList">
              {activeWorkspace.lessons.map((lesson, index) => {
                const lessonBlockCount = lessonBlockCounts.get(lesson.id) ?? 0;
                const displayName = lesson.title || `Lesson ${index + 1}`;
                return (
                  <button
                    className={`lessonRow${
                      lesson.id === activeLesson.id ? " selected" : ""
                    }`}
                    type="button"
                    key={lesson.id}
                    aria-label={`${displayName} ${lesson.key} ${lessonBlockCount} ${
                      lessonBlockCount === 1 ? "block" : "blocks"
                    }`}
                    onClick={() => handleSelectLesson(lesson.id)}
                  >
                    <span>{displayName}</span>
                    <small>{lesson.key || "lesson"}</small>
                    <em>
                      {lessonBlockCount} {lessonBlockCount === 1 ? "block" : "blocks"}
                    </em>
                  </button>
                );
              })}
            </div>

            <div className="exportShape">
              <strong>Export files</strong>
              <span>bundle.yaml</span>
              {lessons.map((lesson) => (
                <span key={lesson.id}>
                  lessons/{lesson.key || "lesson"}.yaml
                </span>
              ))}
            </div>
          </aside>
        ) : null}

        <button
          className="panelEdgeToggle"
          type="button"
          aria-label={bundlePanelVisible ? "Hide bundle panel" : "Show bundle panel"}
          title={bundlePanelVisible ? "Hide bundle panel" : "Show bundle panel"}
          onClick={() => setBundlePanelVisible((visible) => !visible)}
        >
          {bundlePanelVisible ? (
            <ChevronLeft size={16} />
          ) : (
            <ChevronRight size={16} />
          )}
        </button>

        <section className="workspacePanel" aria-label="Block workspace">
          <BlocklyWorkspace
            key={activeLesson.id}
            blockDefinitions={blockDefinitions}
            toolbox={toolbox}
            initialXml={activeLesson.workspaceXml}
            mainRootBlockTypes={mainRootBlockTypes}
            branchReferenceConfig={branchReferenceConfig}
            connectionShapes={loaded.connectionShapes}
            theme={tutorialThemes[themeMode]}
            onWorkspaceChanged={handleWorkspaceChanged}
          />
        </section>
      </section>

      <NamingDialog
        kind={namingDialog ?? "workspace"}
        open={namingDialog !== null}
        onCancel={() => setNamingDialog(null)}
        onCreate={
          namingDialog === "lesson" ? handleCreateLesson : handleCreateWorkspace
        }
      />
    </main>
  );
}

function readThemeMode(): TutorialThemeMode {
  let saved: string | null = null;
  try {
    saved = globalThis.localStorage?.getItem("neuralese-theme") ?? null;
  } catch {
    saved = null;
  }
  if (saved === "dark" || saved === "light") return saved;
  return globalThis.matchMedia?.("(prefers-color-scheme: light)").matches
    ? "light"
    : "dark";
}

function writeThemeMode(mode: TutorialThemeMode): void {
  try {
    globalThis.localStorage?.setItem("neuralese-theme", mode);
  } catch {
    // Theme persistence is optional in restricted browser contexts.
  }
}

function PanelTitle({ icon, title }: { icon: ReactNode; title: string }) {
  return (
    <div className="panelTitle">
      {icon}
      <span>{title}</span>
    </div>
  );
}

function Field({
  label,
  value,
  onChange,
}: {
  label: string;
  value: string;
  onChange: (value: string) => void;
}) {
  return (
    <label className="field">
      <span>{label}</span>
      <input
        aria-label={label}
        value={value}
        onChange={(event) => onChange(event.target.value)}
      />
    </label>
  );
}

function slugify(value: string): string {
  return value
    .toLowerCase()
    .trim()
    .replace(/[^a-z0-9_ -]/g, "")
    .replace(/[\s-]+/g, "_")
    .replace(/^_+|_+$/g, "");
}

function visibleBlockCount(
  blocks: AstBlock[],
  rootBlockTypes: readonly string[],
): number {
  const rootCount = blocks.filter((block) => rootBlockTypes.includes(block.type)).length;
  return Math.max(0, countBlocks(blocks) - rootCount);
}

function countBlocks(blocks: AstBlock[]): number {
  return blocks.reduce((sum, block) => {
    const children = Object.values(block.inputs).flat();
    return sum + 1 + countBlocks(children);
  }, 0);
}
