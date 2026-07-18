import {
  ContinuousFlyout,
  ContinuousMetrics,
  ContinuousToolbox,
  registerContinuousToolbox,
} from "@blockly/continuous-toolbox";
import * as Blockly from "blockly";
import { useEffect, useRef } from "react";
import type { ConnectionShapeSchema } from "../core/schemaTypes";
import {
  configureTutorialRenderer,
  TUTORIAL_RENDERER_NAME,
} from "./tutorialRenderer";
import { tutorialRendererOverrides } from "./tutorialTheme";
import { registerBlocklyEditorShortcuts } from "./registerBlocklyShortcuts";
import {
  refreshBranchReferenceFields,
  type BranchReferenceConfig,
} from "./branchReferences";

registerContinuousToolbox();

const TUTORIAL_FLYOUT_SCALE = 0.65;

export class TutorialContinuousFlyout extends ContinuousFlyout {
  override getFlyoutScale(): number {
    return TUTORIAL_FLYOUT_SCALE;
  }
}

export const continuousToolboxPlugins = {
  flyoutsVerticalToolbox: TutorialContinuousFlyout,
  metricsManager: ContinuousMetrics,
  toolbox: ContinuousToolbox,
};

type BlocklyWorkspaceProps = {
  blockDefinitions: any[];
  toolbox: any;
  initialXml: string;
  mainRootBlockTypes: string[];
  branchReferenceConfig: BranchReferenceConfig;
  connectionShapes: ReadonlyMap<string, ConnectionShapeSchema>;
  theme: Blockly.Theme;
  onWorkspaceChanged: (workspace: Blockly.WorkspaceSvg) => void;
};

export function BlocklyWorkspace({
  blockDefinitions,
  toolbox,
  initialXml,
  mainRootBlockTypes,
  branchReferenceConfig,
  connectionShapes,
  theme,
  onWorkspaceChanged,
}: BlocklyWorkspaceProps) {
  const containerRef = useRef<HTMLDivElement | null>(null);
  const workspaceRef = useRef<Blockly.WorkspaceSvg | null>(null);
  const onWorkspaceChangedRef = useRef(onWorkspaceChanged);

  useEffect(() => {
    onWorkspaceChangedRef.current = onWorkspaceChanged;
  }, [onWorkspaceChanged]);

  useEffect(() => {
    workspaceRef.current?.setTheme(theme);
  }, [theme]);

  useEffect(() => {
    for (const def of blockDefinitions) {
      delete (Blockly.Blocks as Record<string, unknown>)[def.type];
    }
    Blockly.common.defineBlocksWithJsonArray(blockDefinitions);
  }, [blockDefinitions]);

  useEffect(() => {
    if (!containerRef.current || workspaceRef.current) return;

    registerBlocklyEditorShortcuts();
    unregisterBlocklyContextMenuItems([
      "blockCollapseExpand",
      "blockComment",
      "blockDisable",
      "collapseWorkspace",
      "expandWorkspace",
    ]);
    configureTutorialRenderer(connectionShapes);
    const workspace = Blockly.inject(containerRef.current, {
      toolbox,
      plugins: continuousToolboxPlugins,
      theme,
      trashcan: true,
      scrollbars: true,
      renderer: TUTORIAL_RENDERER_NAME,
      rendererOverrides: tutorialRendererOverrides,
      grid: {
        spacing: 36,
        length: 2,
        colour: "#373b40",
        snap: true,
      },
      move: {
        scrollbars: true,
        drag: true,
        wheel: true,
      },
      zoom: {
        controls: true,
        wheel: true,
        startScale: 0.84,
        maxScale: 1.35,
        minScale: 0.55,
        scaleSpeed: 1.12,
      },
    });

    if (initialXml.trim()) {
      const xml = Blockly.utils.xml.textToDom(initialXml);
      Blockly.Xml.domToWorkspace(xml, workspace);
    }

    refreshBranchReferenceFields(workspace, branchReferenceConfig);
    enforceWorkspaceInvariants(workspace, mainRootBlockTypes);
    let workspaceUpdateTask: ReturnType<typeof globalThis.setTimeout> | undefined;
    const scheduleWorkspaceUpdate = () => {
      if (workspaceUpdateTask !== undefined) {
        globalThis.clearTimeout(workspaceUpdateTask);
      }
      workspaceUpdateTask = globalThis.setTimeout(() => {
        workspaceUpdateTask = undefined;
        enforceWorkspaceInvariants(workspace, mainRootBlockTypes);
        onWorkspaceChangedRef.current(workspace);
      }, 0);
    };
    const cancelWorkspaceUpdate = () => {
      if (workspaceUpdateTask === undefined) return;
      globalThis.clearTimeout(workspaceUpdateTask);
      workspaceUpdateTask = undefined;
    };
    const scheduler = new WorkspaceChangeScheduler(
      scheduleWorkspaceUpdate,
      cancelWorkspaceUpdate,
    );
    const viewportLock = new BlockDragViewportLock();
    const restoreTrashLayer = moveTrashAboveDraggedBlocks(containerRef.current);
    const stopMiddleButtonBlockPan = installMiddleButtonBlockPan(
      containerRef.current,
      workspace,
    );
    let refreshingBranchReferences = false;
    const trashCloseTasks = new Set<ReturnType<typeof globalThis.setTimeout>>();
    const scheduleTrashClose = (delay: number) => {
      const task = globalThis.setTimeout(() => {
        trashCloseTasks.delete(task);
        closeTrashLidCompletely(workspace.trashcan);
      }, delay);
      trashCloseTasks.add(task);
    };
    const listener = (event: Blockly.Events.Abstract) => {
      if (event.type === Blockly.Events.BLOCK_DELETE) {
        scheduleTrashClose(0);
        scheduleTrashClose(120);
      }
      if (event.type === Blockly.Events.BLOCK_DRAG) {
        updateInsertionMarkerAccent(
          workspace,
          event as Blockly.Events.BlockDrag,
        );
        if ((event as Blockly.Events.BlockDrag).isStart === false) {
          scheduleTrashClose(120);
        }
      }
      if (
        !refreshingBranchReferences &&
        shouldRefreshBranchReferences(event)
      ) {
        refreshingBranchReferences = true;
        try {
          Blockly.Events.disable();
          refreshBranchReferenceFields(workspace, branchReferenceConfig);
        } finally {
          Blockly.Events.enable();
          refreshingBranchReferences = false;
        }
      }
      viewportLock.handle(event, workspace);
      if (event.type === Blockly.Events.VIEWPORT_CHANGE && containerRef.current) {
        updateWorkspaceBackgroundParallax(containerRef.current, workspace);
      }
      scheduler.handle(event);
    };

    workspace.addChangeListener(listener);
    workspaceRef.current = workspace;
    updateWorkspaceBackgroundParallax(containerRef.current, workspace);
    onWorkspaceChangedRef.current(workspace);
    const stopObservingSize = observeWorkspaceSize(
      containerRef.current,
      () => Blockly.svgResize(workspace),
    );

    return () => {
      if (workspaceUpdateTask !== undefined) {
        globalThis.clearTimeout(workspaceUpdateTask);
      }
      trashCloseTasks.forEach((task) => globalThis.clearTimeout(task));
      trashCloseTasks.clear();
      stopObservingSize();
      stopMiddleButtonBlockPan();
      restoreTrashLayer();
      workspace.removeChangeListener(listener);
      workspace.dispose();
      workspaceRef.current = null;
    };
  }, [branchReferenceConfig, connectionShapes, mainRootBlockTypes, toolbox]);

  return <div ref={containerRef} className="blocklyHost" />;
}

export function updateWorkspaceBackgroundParallax(
  container: HTMLElement,
  workspace: Blockly.WorkspaceSvg,
): void {
  const parallaxScale = 0.32;
  container.style.setProperty(
    "--workspace-grid-x",
    `${workspace.scrollX * parallaxScale}px`,
  );
  container.style.setProperty(
    "--workspace-grid-y",
    `${workspace.scrollY * parallaxScale}px`,
  );
}

type TrashLidController = {
  closeLid(): void;
  setLidOpen(state: boolean): void;
  setMinOpenness(value: number): void;
};

export function closeTrashLidCompletely(
  trash: Blockly.Trashcan | null | undefined,
): void {
  if (!trash) return;
  const controller = trash as unknown as TrashLidController;
  controller.setMinOpenness(0);
  controller.setLidOpen(false);
  controller.closeLid();
}

export function moveTrashAboveDraggedBlocks(container: HTMLElement): () => void {
  const trash = container.querySelector<SVGGElement>(".blocklyTrash");
  const dragSurface = container.querySelector<SVGSVGElement>(
    ".blocklyBlockDragSurface",
  );
  if (!trash || !dragSurface || !trash.parentNode) return () => {};

  const originalParent = trash.parentNode;
  const originalNextSibling = trash.nextSibling;
  dragSurface.appendChild(trash);

  return () => {
    if (originalNextSibling?.parentNode === originalParent) {
      originalParent.insertBefore(trash, originalNextSibling);
    } else {
      originalParent.appendChild(trash);
    }
  };
}

export function installMiddleButtonBlockPan(
  container: HTMLElement,
  workspace: Pick<Blockly.WorkspaceSvg, "scroll" | "scrollX" | "scrollY">,
): () => void {
  let pointerId: number | null = null;
  let startPointerX = 0;
  let startPointerY = 0;
  let startScrollX = 0;
  let startScrollY = 0;

  const isMainWorkspaceBlock = (target: EventTarget | null): boolean => {
    if (!(target instanceof Element)) return false;
    const block = target.closest(".blocklyDraggable");
    return !!block && !block.closest(".blocklyFlyout");
  };

  const onPointerDown = (event: PointerEvent) => {
    if (event.button !== 1 || !isMainWorkspaceBlock(event.target)) return;
    pointerId = event.pointerId;
    startPointerX = event.clientX;
    startPointerY = event.clientY;
    startScrollX = workspace.scrollX;
    startScrollY = workspace.scrollY;
    container.classList.add("middleButtonPanning");
    event.preventDefault();
    event.stopImmediatePropagation();
  };

  const onPointerMove = (event: PointerEvent) => {
    if (pointerId === null || event.pointerId !== pointerId) return;
    workspace.scroll(
      startScrollX + event.clientX - startPointerX,
      startScrollY + event.clientY - startPointerY,
    );
    event.preventDefault();
    event.stopImmediatePropagation();
  };

  const finishPan = (event: PointerEvent) => {
    if (pointerId === null || event.pointerId !== pointerId) return;
    pointerId = null;
    container.classList.remove("middleButtonPanning");
    event.preventDefault();
    event.stopImmediatePropagation();
  };

  const onAuxClick = (event: MouseEvent) => {
    if (event.button !== 1 || !isMainWorkspaceBlock(event.target)) return;
    event.preventDefault();
    event.stopImmediatePropagation();
  };

  container.addEventListener("pointerdown", onPointerDown, true);
  container.addEventListener("auxclick", onAuxClick, true);
  document.addEventListener("pointermove", onPointerMove, true);
  document.addEventListener("pointerup", finishPan, true);
  document.addEventListener("pointercancel", finishPan, true);

  return () => {
    container.classList.remove("middleButtonPanning");
    container.removeEventListener("pointerdown", onPointerDown, true);
    container.removeEventListener("auxclick", onAuxClick, true);
    document.removeEventListener("pointermove", onPointerMove, true);
    document.removeEventListener("pointerup", finishPan, true);
    document.removeEventListener("pointercancel", finishPan, true);
  };
}

export function updateInsertionMarkerAccent(
  workspace: Blockly.WorkspaceSvg,
  event: Blockly.Events.BlockDrag,
): void {
  if (!event.isStart) return;
  const block =
    (event.blockId ? workspace.getBlockById(event.blockId) : null) ??
    event.blocks?.find((candidate) => candidate.workspace === workspace) ??
    event.blocks?.[0];
  if (!(block instanceof Blockly.BlockSvg)) return;
  workspace
    .getParentSvg()
    .style.setProperty("--blockly-insertion-marker-accent", block.getColourTertiary());
}

function unregisterBlocklyContextMenuItems(ids: string[]): void {
  const registry = Blockly.ContextMenuRegistry.registry;
  for (const id of ids) {
    if (!registry.getItem(id)) continue;
    registry.unregister(id);
  }
}

type WorkspaceEvent = Pick<Blockly.Events.Abstract, "type" | "isUiEvent"> & {
  isStart?: boolean;
};

export class WorkspaceChangeScheduler {
  private blockDragActive = false;

  constructor(
    private readonly scheduleUpdate: () => void,
    private readonly cancelUpdate: () => void = () => {},
  ) {}

  handle(event: WorkspaceEvent): void {
    if (event.type === Blockly.Events.BLOCK_DRAG) {
      if (event.isStart) {
        this.blockDragActive = true;
        this.cancelUpdate();
        return;
      }
      this.blockDragActive = false;
      this.scheduleUpdate();
      return;
    }
    if (this.blockDragActive) return;
    if (shouldScheduleWorkspaceUpdate(event)) {
      this.scheduleUpdate();
    }
  }
}

export class BlockDragViewportLock {
  private blockDragActive = false;
  private scrollX = 0;
  private scrollY = 0;

  handle(event: WorkspaceEvent, workspace: Blockly.WorkspaceSvg): void {
    if (event.type === Blockly.Events.BLOCK_DRAG) {
      this.blockDragActive = event.isStart === true;
      if (this.blockDragActive) {
        this.scrollX = workspace.scrollX;
        this.scrollY = workspace.scrollY;
      }
      return;
    }
    if (
      this.blockDragActive &&
      event.type === Blockly.Events.VIEWPORT_CHANGE &&
      (workspace.scrollX !== this.scrollX || workspace.scrollY !== this.scrollY)
    ) {
      workspace.scroll(this.scrollX, this.scrollY);
    }
  }
}

export function shouldScheduleWorkspaceUpdate(
  event: WorkspaceEvent,
): boolean {
  if (event.type === Blockly.Events.BLOCK_DRAG) {
    return event.isStart === false;
  }
  if (event.type === Blockly.Events.BLOCK_CREATE) {
    return false;
  }
  return !event.isUiEvent;
}

export function shouldRefreshBranchReferences(event: WorkspaceEvent): boolean {
  return (
    event.type === Blockly.Events.BLOCK_CREATE ||
    event.type === Blockly.Events.BLOCK_DELETE ||
    event.type === Blockly.Events.BLOCK_CHANGE ||
    event.type === Blockly.Events.FINISHED_LOADING
  );
}

export function observeWorkspaceSize(
  container: Element,
  onResize: () => void,
  ResizeObserverClass: typeof ResizeObserver = globalThis.ResizeObserver,
): () => void {
  onResize();
  const observer = new ResizeObserverClass(onResize);
  observer.observe(container);
  return () => observer.disconnect();
}

export function enforceWorkspaceInvariants(
  workspace: Blockly.WorkspaceSvg,
  rootBlockTypes: string[],
): void {
  const rootTypes = new Set(rootBlockTypes);
  const topBlocks = workspace.getTopBlocks(true).filter((block) => !block.isInFlyout);
  const roots = topBlocks.filter((block) => rootTypes.has(block.type));

  roots.forEach((root, index) => {
    if (index > 0) {
      root.dispose(false);
      return;
    }
    root.setDeletable(false);
    root.setMovable(false);
    root.contextMenu = false;
  });
}
