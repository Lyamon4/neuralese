import { fireEvent, render, screen, within } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { App } from "../app/App";

vi.mock("../blockly/BlocklyWorkspace", () => ({
  BlocklyWorkspace: () => <div data-testid="block-workspace" />,
}));

describe("App workspace shell", () => {
  beforeEach(() => {
    localStorage.clear();
    delete document.documentElement.dataset.theme;
  });

  it("creates a named workspace with its first lesson", () => {
    render(<App />);

    fireEvent.click(screen.getByRole("button", { name: "Add workspace" }));

    const dialog = screen.getByRole("dialog", { name: "Create workspace" });
    fireEvent.change(within(dialog).getByLabelText("Workspace name"), {
      target: { value: "Image Classifier" },
    });
    fireEvent.click(within(dialog).getByRole("button", { name: "Create" }));

    expect(screen.queryByRole("dialog", { name: "Create workspace" })).toBeNull();
    const selectedWorkspace = screen.getByRole("button", {
      name: "Image Classifier 1 lesson 0 blocks",
    });
    expect(selectedWorkspace.classList.contains("selected")).toBe(true);
    const selectedLesson = screen.getByRole("button", {
      name: "Image Classifier image_classifier 0 blocks",
    });
    expect(selectedLesson.classList.contains("selected")).toBe(true);
    expect(screen.getByText("2 workspaces · 2 lessons · 0 blocks")).toBeTruthy();
  });

  it("creates a lesson inside the selected workspace with an automatic key", () => {
    render(<App />);

    fireEvent.click(screen.getByRole("button", { name: "Add lesson" }));

    const dialog = screen.getByRole("dialog", { name: "Create lesson" });
    fireEvent.change(within(dialog).getByLabelText("Lesson name"), {
      target: { value: "Model basics" },
    });
    fireEvent.click(within(dialog).getByRole("button", { name: "Create" }));

    expect(screen.queryByRole("dialog", { name: "Create lesson" })).toBeNull();
    const selectedLesson = screen.getByRole("button", {
      name: "Model basics model_basics 0 blocks",
    });
    expect(selectedLesson.classList.contains("selected")).toBe(true);
    expect(screen.getByText("1 workspace · 2 lessons · 0 blocks")).toBeTruthy();
    expect(screen.getByText("lessons/model_basics.yaml")).toBeTruthy();
  });

  it("keeps workspace deletion inside the bundle and preserves one workspace", () => {
    render(<App />);

    const deleteButton = screen.getByRole("button", {
      name: "Delete selected workspace",
    });
    expect((deleteButton as HTMLButtonElement).disabled).toBe(true);

    fireEvent.click(screen.getByRole("button", { name: "Add workspace" }));
    fireEvent.change(screen.getByLabelText("Workspace name"), {
      target: { value: "Second workspace" },
    });
    fireEvent.click(screen.getByRole("button", { name: "Create" }));

    expect((deleteButton as HTMLButtonElement).disabled).toBe(false);
    fireEvent.click(deleteButton);

    expect(screen.queryByText("Second workspace")).toBeNull();
    expect(screen.getByText("Intro workspace")).toBeTruthy();
    expect((deleteButton as HTMLButtonElement).disabled).toBe(true);
  });

  it("deletes lessons but preserves one lesson in every workspace", () => {
    render(<App />);

    const deleteLessonButton = screen.getByRole("button", {
      name: "Delete selected lesson",
    });
    expect((deleteLessonButton as HTMLButtonElement).disabled).toBe(true);

    fireEvent.click(screen.getByRole("button", { name: "Add lesson" }));
    fireEvent.change(screen.getByLabelText("Lesson name"), {
      target: { value: "Second lesson" },
    });
    fireEvent.click(screen.getByRole("button", { name: "Create" }));

    expect((deleteLessonButton as HTMLButtonElement).disabled).toBe(false);
    fireEvent.click(deleteLessonButton);

    expect(screen.queryByText("Second lesson")).toBeNull();
    expect(screen.getByText("Intro lesson")).toBeTruthy();
    expect((deleteLessonButton as HTMLButtonElement).disabled).toBe(true);
  });

  it("collapses from the Bundle panel and restores from the workspace edge", () => {
    const { container } = render(<App />);
    const editorGrid = container.querySelector(".editorGrid");

    expect(container.querySelector(".leftPanel")).toBeTruthy();
    const hidePanelButton = screen.getByRole("button", {
      name: "Hide bundle panel",
    });
    expect(hidePanelButton.closest(".editorGrid")).toBe(editorGrid);
    fireEvent.click(hidePanelButton);

    expect(container.querySelector(".leftPanel")).toBeNull();
    expect(container.querySelector(".editorGrid")?.classList.contains("bundleHidden")).toBe(true);

    const showPanelButton = screen.getByRole("button", {
      name: "Show bundle panel",
    });
    expect(showPanelButton.closest(".editorGrid")).toBe(editorGrid);
    fireEvent.click(showPanelButton);

    expect(container.querySelector(".leftPanel")).toBeTruthy();
    expect(container.querySelector(".editorGrid")?.classList.contains("bundleHidden")).toBe(false);
  });

  it("moves export files into Bundle and removes the Lesson panel", () => {
    const { container } = render(<App />);
    const bundlePanel = container.querySelector(".leftPanel");

    expect(within(bundlePanel as HTMLElement).getByText("Export files")).toBeTruthy();
    expect(within(bundlePanel as HTMLElement).getByText("bundle.yaml")).toBeTruthy();
    expect(
      within(bundlePanel as HTMLElement).getByText("lessons/intro_lesson.yaml"),
    ).toBeTruthy();
    expect(screen.queryByText("Lesson", { selector: ".panelTitle span" })).toBeNull();
    expect(container.querySelector(".rightPanel")).toBeNull();
  });

  it("shows validation issues from a compact top warning", () => {
    render(<App />);

    const trigger = screen.getByRole("button", { name: "Show 2 validation issues" });
    expect(trigger.closest(".topbarActions")).toBeTruthy();

    fireEvent.click(trigger);

    const popover = screen.getByRole("alert", { name: "Validation issues" });
    expect(within(popover).getAllByRole("listitem")).toHaveLength(2);
    expect(popover.textContent).not.toMatch(/\blesson\b/i);
    expect(screen.getByRole("button", { name: "Hide validation issues" })).toBeTruthy();
  });

  it("switches and persists the generated light theme", () => {
    render(<App />);

    fireEvent.click(screen.getByRole("button", { name: "Use light theme" }));

    expect(document.documentElement.dataset.theme).toBe("light");
    expect(document.documentElement.style.getPropertyValue("--bg-deep")).toBe(
      "#e8ebef",
    );
    expect(localStorage.getItem("neuralese-theme")).toBe("light");
    expect(screen.getByRole("button", { name: "Use dark theme" })).toBeTruthy();
  });
});
