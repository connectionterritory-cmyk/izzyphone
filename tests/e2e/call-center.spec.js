const { test, expect } = require("@playwright/test");

const TEST_PROJECT_REF = process.env.IZZY_TEST_PROJECT_REF || "";
const CALL_CENTER_LEAD_QUERY = process.env.IZZY_TEST_CALL_CENTER_LEAD_QUERY || "";

function hasLoginCreds() {
  return Boolean(process.env.IZZY_TEST_PIN && process.env.IZZY_TEST_PASSWORD);
}

function hasCallCenterLeadQuery() {
  return Boolean(CALL_CENTER_LEAD_QUERY.trim());
}

async function primeEnvironment(page) {
  if (!TEST_PROJECT_REF) return;
  await page.addInitScript((projectRef) => {
    window.localStorage.setItem("izzy_project_ref", projectRef);
    window.sessionStorage.setItem("izzy_project_ref", projectRef);
  }, TEST_PROJECT_REF);
}

async function login(page) {
  await primeEnvironment(page);
  await page.goto("/index.html");
  await expect(page.locator(".pin-title").first()).toHaveText(/Izzy Communications/i);
  await page.locator('input[type="text"], input[placeholder*="COD"], input[placeholder*="codigo" i]').first().fill(process.env.IZZY_TEST_PIN);
  await page.locator('input[type="password"]').first().fill(process.env.IZZY_TEST_PASSWORD);
  await page.getByRole("button", { name: /entrar/i }).click();
  await page.waitForLoadState("networkidle");
}

function formatInputDate(value) {
  const pad = (n) => String(n).padStart(2, "0");
  return [
    value.getFullYear(),
    pad(value.getMonth() + 1),
    pad(value.getDate()),
  ].join("-") + `T${pad(value.getHours())}:${pad(value.getMinutes())}`;
}

function expectedShortDate(value) {
  return new Intl.DateTimeFormat("en-US", {
    year: "2-digit",
    month: "numeric",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
  }).format(value);
}

async function openLeadFromWorkspace(page, query) {
  await page.goto("/call-center.html");
  await page.waitForLoadState("networkidle");
  await expect(page.getByRole("heading", { name: /workspace operativo/i })).toBeVisible();
  await expect(page.locator("#appNav")).toBeVisible();

  await page.locator("#searchInput").fill(query);
  const row = page.locator("#tableBody tr").first();
  await expect(row).toBeVisible();
  await row.click();
  await expect(page.locator("#leadModal")).toHaveClass(/open/);
  await expect(page.locator("#timelineList")).not.toContainText(/cargando timeline/i);
}

test.describe("call center smoke", () => {
  test.skip(!hasLoginCreds(), "Set IZZY_TEST_PIN and IZZY_TEST_PASSWORD to run Call Center smoke checks.");
  test.skip(!hasCallCenterLeadQuery(), "Set IZZY_TEST_CALL_CENTER_LEAD_QUERY to target a stable staging lead for Call Center smoke checks.");

  test("agent can schedule and complete follow-ups with recalculation", async ({ page }) => {
    await login(page);
    await expect(page.locator("#appNav")).toBeVisible();

    const now = Date.now();
    const firstDate = new Date(now + 60 * 60 * 1000);
    const secondDate = new Date(now + 2 * 60 * 60 * 1000);
    const subjectA = `Smoke Followup A ${now}`;
    const subjectB = `Smoke Followup B ${now}`;
    const expectedA = expectedShortDate(firstDate);
    const expectedB = expectedShortDate(secondDate);

    await openLeadFromWorkspace(page, CALL_CENTER_LEAD_QUERY);

    await page.locator("#followupSubjectInput").fill(subjectA);
    await page.locator("#followupDateInput").fill(formatInputDate(firstDate));
    await page.locator("#followupNotesInput").fill("Primer seguimiento smoke.");
    await page.getByRole("button", { name: /programar seguimiento/i }).click();
    await expect(page.locator("#toast")).toContainText(/seguimiento programado/i);
    await expect(page.locator("#timelineList")).toContainText(subjectA);
    await expect(page.locator("#modalNextFollowup")).toContainText(expectedA);

    await page.locator("#followupSubjectInput").fill(subjectB);
    await page.locator("#followupDateInput").fill(formatInputDate(secondDate));
    await page.locator("#followupNotesInput").fill("Segundo seguimiento smoke.");
    await page.getByRole("button", { name: /programar seguimiento/i }).click();
    await expect(page.locator("#toast")).toContainText(/seguimiento programado/i);
    await expect(page.locator("#timelineList")).toContainText(subjectB);
    await expect(page.locator("#modalNextFollowup")).toContainText(expectedA);

    const followupAItem = page.locator(".timeline-item").filter({ hasText: subjectA }).first();
    await expect(followupAItem).toBeVisible();
    page.once("dialog", (dialog) => dialog.accept("Completado desde smoke test"));
    await followupAItem.getByRole("button", { name: /completar/i }).click();

    await expect(page.locator("#toast")).toContainText(/seguimiento completado/i);
    await expect(page.locator("#timelineList")).toContainText(subjectA);
    await expect(page.locator("#modalNextFollowup")).toContainText(expectedB);
  });
});
