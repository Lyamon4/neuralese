import { expect, test } from "@playwright/test";
import JSZip from "jszip";

test("exports a bundle from the default workspace", async ({ page }) => {
  await page.goto("/");
  await expect(page.getByRole("heading", { name: "Neuralese Tutorial Builder" })).toBeVisible();
  await expect(page.getByRole("button", { name: "Export ZIP" })).toBeEnabled();

  const [download] = await Promise.all([
    page.waitForEvent("download"),
    page.getByRole("button", { name: "Export ZIP" }).click(),
  ]);
  const downloadPath = await download.path();
  expect(downloadPath).toBeTruthy();

  const zipBytes = await download.createReadStream();
  const chunks: Buffer[] = [];
  for await (const chunk of zipBytes!) {
    chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
  }
  const zip = await JSZip.loadAsync(Buffer.concat(chunks));

  expect(zip.file("bundle.yaml")).toBeTruthy();
  expect(zip.file("lessons/intro_lesson.yaml")).toBeTruthy();
  await expect(async () => {
    const lessonYaml = await zip.file("lessons/intro_lesson.yaml")?.async("string");
    expect(lessonYaml).toContain("step welcome:");
    expect(lessonYaml).toContain("explain:");
  }).toPass();
});

test("adds lessons inside a named workspace and exports their generated keys", async ({ page }) => {
  await page.goto("/");

  await page.getByRole("button", { name: "Add workspace" }).click();
  const dialog = page.getByRole("dialog", { name: "Create workspace" });
  await dialog.getByLabel("Workspace name").fill("Second workspace");
  await dialog.getByRole("button", { name: "Create" }).click();
  await expect(
    page.getByRole("button", {
      name: "Second workspace 1 lesson 3 blocks",
    }),
  ).toBeVisible();
  await expect(
    page.getByRole("button", {
      name: "Second workspace second_workspace 3 blocks",
    }),
  ).toBeVisible();

  await page.getByRole("button", { name: "Add lesson" }).click();
  const lessonDialog = page.getByRole("dialog", { name: "Create lesson" });
  await lessonDialog.getByLabel("Lesson name").fill("Model basics");
  await lessonDialog.getByRole("button", { name: "Create" }).click();
  await expect(
    page.getByRole("button", {
      name: "Second workspace 2 lessons 6 blocks",
    }),
  ).toBeVisible();
  await expect(
    page.getByRole("button", { name: "Model basics model_basics 3 blocks" }),
  ).toBeVisible();
  await expect(page.getByRole("button", { name: "Export ZIP" })).toBeEnabled();

  const [download] = await Promise.all([
    page.waitForEvent("download"),
    page.getByRole("button", { name: "Export ZIP" }).click(),
  ]);
  const stream = await download.createReadStream();
  const chunks: Buffer[] = [];
  for await (const chunk of stream!) {
    chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
  }
  const zip = await JSZip.loadAsync(Buffer.concat(chunks));

  expect(zip.file("lessons/intro_lesson.yaml")).toBeTruthy();
  expect(zip.file("lessons/second_workspace.yaml")).toBeTruthy();
  expect(zip.file("lessons/model_basics.yaml")).toBeTruthy();
  expect(await zip.file("lessons/second_workspace.yaml")?.async("string")).toContain(
    "lesson_title: Second workspace",
  );
  expect(await zip.file("lessons/model_basics.yaml")?.async("string")).toContain(
    "lesson_title: Model basics",
  );
});

test("editing bundle metadata does not recreate or reset the workspace", async ({ page }) => {
  await page.goto("/");
  const host = page.locator(".blocklyHost");
  await expect(host).toBeVisible();

  await host.hover();
  await page.mouse.wheel(0, -500);
  const blockCanvas = page.locator(".blocklyHost .blocklyBlockCanvas").first();
  const before = await blockCanvas.getAttribute("transform");

  await page.getByLabel("Bundle name").fill("Camera stays put");

  await expect(page.getByLabel("Bundle name")).toHaveValue("Camera stays put");
  await expect(blockCanvas).toHaveAttribute("transform", before ?? "");
});

test("collapses and restores the Bundle panel from the top bar", async ({ page }) => {
  await page.goto("/");

  const panel = page.locator(".leftPanel");
  await panel.getByRole("button", { name: "Hide bundle panel" }).click();
  await expect(panel).toHaveCount(0);

  await page.getByRole("button", { name: "Show bundle panel" }).click();
  await expect(page.locator(".leftPanel")).toBeVisible();
});

test("jumps through the continuously scrolling block catalogue", async ({ page }) => {
  await page.goto("/");

  await expect(page.getByRole("searchbox")).toHaveCount(0);

  const feedbackCategory = page
    .locator(".blocklyToolbox .blocklyToolboxCategory")
    .filter({ hasText: /^Feedback$/ });
  await expect(feedbackCategory).toBeVisible();
  await feedbackCategory.click();

  await expect(feedbackCategory).toHaveClass(/blocklyToolboxSelected/);
  await expect(
    page
      .locator(".blocklyFlyout .blocklyFlyoutLabelText")
      .filter({ hasText: /^Feedback$/ }),
  ).toBeVisible();

  expect(await page.locator(".blocklyFlyout .blocklyDraggable").count()).toBeGreaterThan(20);
});
