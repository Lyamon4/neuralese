import { describe, expect, it, vi } from "vitest";
import {
  closeTrashLidCompletely,
  installMiddleButtonBlockPan,
  moveTrashAboveDraggedBlocks,
  observeWorkspaceSize,
} from "../blockly/BlocklyWorkspace";

describe("workspace resize observer", () => {
  it("resizes Blockly when its container changes size and disconnects on cleanup", () => {
    const container = document.createElement("div");
    const onResize = vi.fn();
    const observe = vi.fn();
    const disconnect = vi.fn();
    let notifyResize: ResizeObserverCallback | undefined;

    class FakeResizeObserver {
      constructor(callback: ResizeObserverCallback) {
        notifyResize = callback;
      }

      observe = observe;
      disconnect = disconnect;
      unobserve = vi.fn();
    }

    const cleanup = observeWorkspaceSize(
      container,
      onResize,
      FakeResizeObserver as unknown as typeof ResizeObserver,
    );

    expect(observe).toHaveBeenCalledWith(container);
    expect(onResize).toHaveBeenCalledTimes(1);

    notifyResize?.([], {} as ResizeObserver);
    expect(onResize).toHaveBeenCalledTimes(2);

    cleanup();
    expect(disconnect).toHaveBeenCalledTimes(1);
  });

  it("pans the workspace instead of starting a block drag with the middle button", () => {
    const container = document.createElement("div");
    const block = document.createElement("div");
    block.className = "blocklyDraggable";
    container.appendChild(block);
    document.body.appendChild(container);

    const scroll = vi.fn();
    const blockPointerDown = vi.fn();
    block.addEventListener("pointerdown", blockPointerDown);
    const cleanup = installMiddleButtonBlockPan(container, {
      scroll,
      scrollX: 10,
      scrollY: 20,
    });

    block.dispatchEvent(pointerEvent("pointerdown", 1, 7, 100, 100));
    document.dispatchEvent(pointerEvent("pointermove", 0, 7, 125, 130));

    expect(blockPointerDown).not.toHaveBeenCalled();
    expect(scroll).toHaveBeenCalledWith(35, 50);
    expect(container.classList.contains("middleButtonPanning")).toBe(true);

    document.dispatchEvent(pointerEvent("pointerup", 1, 7, 125, 130));
    expect(container.classList.contains("middleButtonPanning")).toBe(false);

    block.dispatchEvent(pointerEvent("pointerdown", 0, 8, 100, 100));
    expect(blockPointerDown).toHaveBeenCalledTimes(1);

    cleanup();
    container.remove();
  });

  it("paints the trash above the dragged-block surface and restores it on cleanup", () => {
    const container = document.createElement("div");
    const workspaceSvg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
    const trash = document.createElementNS("http://www.w3.org/2000/svg", "g");
    const dragSurface = document.createElementNS("http://www.w3.org/2000/svg", "svg");
    trash.classList.add("blocklyTrash");
    dragSurface.classList.add("blocklyBlockDragSurface");
    workspaceSvg.appendChild(trash);
    container.append(workspaceSvg, dragSurface);

    const cleanup = moveTrashAboveDraggedBlocks(container);

    expect(trash.parentNode).toBe(dragSurface);

    cleanup();
    expect(trash.parentNode).toBe(workspaceSvg);
  });

  it("fully closes a trash lid without clearing its contents", () => {
    const trash = {
      setMinOpenness: vi.fn(),
      setLidOpen: vi.fn(),
      closeLid: vi.fn(),
    };

    closeTrashLidCompletely(trash as never);

    expect(trash.setMinOpenness).toHaveBeenCalledWith(0);
    expect(trash.setLidOpen).toHaveBeenCalledWith(false);
    expect(trash.closeLid).toHaveBeenCalledTimes(1);
  });
});

function pointerEvent(
  type: string,
  button: number,
  pointerId: number,
  clientX: number,
  clientY: number,
): Event {
  const event = new Event(type, { bubbles: true, cancelable: true });
  Object.defineProperties(event, {
    button: { value: button },
    pointerId: { value: pointerId },
    clientX: { value: clientX },
    clientY: { value: clientY },
  });
  return event;
}
