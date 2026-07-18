import { describe, expect, it, vi } from "vitest";
import {
  BlockDragViewportLock,
  enforceWorkspaceInvariants,
  WorkspaceChangeScheduler,
  shouldScheduleWorkspaceUpdate,
} from "../blockly/BlocklyWorkspace";

describe("workspace invariants", () => {
  it("keeps one protected main root without deleting branch roots or detached blocks", () => {
    const root = {
      type: "lesson_root",
      isInFlyout: false,
      setDeletable: vi.fn(),
      setMovable: vi.fn(),
      contextMenu: true,
      dispose: vi.fn(),
    };
    const duplicateRoot = {
      ...root,
      setDeletable: vi.fn(),
      setMovable: vi.fn(),
      dispose: vi.fn(),
    };
    const orphan = {
      type: "action_explain",
      isInFlyout: false,
      dispose: vi.fn(),
    };
    const branchRoot = {
      type: "lesson_branch",
      isInFlyout: false,
      dispose: vi.fn(),
    };
    const workspace = {
      getTopBlocks: () => [root, duplicateRoot, branchRoot, orphan],
    };

    enforceWorkspaceInvariants(workspace as never, ["lesson_root"]);

    expect(root.setDeletable).toHaveBeenCalledWith(false);
    expect(root.setMovable).toHaveBeenCalledWith(false);
    expect(root.contextMenu).toBe(false);
    expect(duplicateRoot.dispose).toHaveBeenCalledWith(false);
    expect(branchRoot.dispose).not.toHaveBeenCalled();
    expect(orphan.dispose).not.toHaveBeenCalled();
  });

  it("waits until a dragged block is dropped before updating React state", () => {
    expect(
      shouldScheduleWorkspaceUpdate({
        type: "create",
        isUiEvent: false,
      } as never),
    ).toBe(false);
    expect(
      shouldScheduleWorkspaceUpdate({
        type: "drag",
        isUiEvent: true,
        isStart: true,
      } as never),
    ).toBe(false);
    expect(
      shouldScheduleWorkspaceUpdate({
        type: "drag",
        isUiEvent: true,
        isStart: false,
      } as never),
    ).toBe(true);
    expect(
      shouldScheduleWorkspaceUpdate({
        type: "move",
        isUiEvent: false,
      } as never),
    ).toBe(true);
    expect(
      shouldScheduleWorkspaceUpdate({
        type: "change",
        isUiEvent: false,
      } as never),
    ).toBe(true);
    expect(
      shouldScheduleWorkspaceUpdate({
        type: "block_field_intermediate_change",
        isUiEvent: false,
      } as never),
    ).toBe(true);
    expect(
      shouldScheduleWorkspaceUpdate({
        type: "delete",
        isUiEvent: false,
      } as never),
    ).toBe(true);
  });

  it("does not update React state while a block drag is active", () => {
    const schedule = vi.fn();
    const scheduler = new WorkspaceChangeScheduler(schedule);

    scheduler.handle({
      type: "drag",
      isUiEvent: true,
      isStart: true,
    } as never);
    scheduler.handle({
      type: "move",
      isUiEvent: false,
    } as never);
    scheduler.handle({
      type: "change",
      isUiEvent: false,
    } as never);

    expect(schedule).not.toHaveBeenCalled();

    scheduler.handle({
      type: "drag",
      isUiEvent: true,
      isStart: false,
    } as never);

    expect(schedule).toHaveBeenCalledTimes(1);
  });

  it("restores the camera when the viewport moves during a block drag", () => {
    const scroll = vi.fn();
    const workspace = {
      scrollX: -120,
      scrollY: -80,
      scroll,
    };
    const lock = new BlockDragViewportLock();

    lock.handle(
      {
        type: "drag",
        isUiEvent: true,
        isStart: true,
      } as never,
      workspace as never,
    );

    workspace.scrollX = -180;
    workspace.scrollY = -130;
    lock.handle(
      {
        type: "viewport_change",
        isUiEvent: true,
      } as never,
      workspace as never,
    );

    expect(scroll).toHaveBeenCalledWith(-120, -80);
  });
});
