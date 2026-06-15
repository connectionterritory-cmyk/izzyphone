const { test, expect } = require("@playwright/test");

function hasLoginCreds() {
  return Boolean(process.env.IZZY_TEST_PIN && process.env.IZZY_TEST_PASSWORD);
}

async function login(page) {
  await page.goto("/index.html");
  await expect(page.locator(".pin-title").first()).toHaveText(/Izzy Communications/i);
  await page.locator('input[type="text"], input[placeholder*="COD"], input[placeholder*="codigo" i]').first().fill(process.env.IZZY_TEST_PIN);
  await page.locator('input[type="password"]').first().fill(process.env.IZZY_TEST_PASSWORD);
  await page.getByRole("button", { name: /entrar/i }).click();
  await page.waitForLoadState("networkidle");
}

test.describe("portal smoke", () => {
  test("login page renders", async ({ page }) => {
    await page.goto("/index.html");
    await expect(page.locator(".pin-title").first()).toHaveText(/Izzy Communications/i);
    await expect(page.getByRole("button", { name: /entrar/i })).toBeVisible();
  });

  test("compensation public route should not blank-screen before login", async ({ page }) => {
    await page.goto("/compensation.html?tab=tree");
    await page.waitForLoadState("domcontentloaded");
    await expect(page).toHaveURL(/(compensation\.html|index\.html)/);
  });
});

test.describe("authenticated portal", () => {
  test.skip(!hasLoginCreds(), "Set IZZY_TEST_PIN and IZZY_TEST_PASSWORD to run authenticated portal checks.");

  test.beforeEach(async ({ page }) => {
    await login(page);
    await expect(page.locator("#appNav")).toBeVisible();
  });

  test("compensation tree is reachable after login", async ({ page }) => {
    await page.goto("/compensation.html?tab=tree");
    await page.waitForLoadState("networkidle");
    await expect(page).not.toHaveURL(/index\.html/);
    await expect(page.getByText(/plan de compensaci[oó]n/i)).toBeVisible();
    await expect(page.getByText(/mi [áa]rbol/i)).toBeVisible();
  });

  test("compensation route does not bounce back to login", async ({ page }) => {
    await page.goto("/compensation.html?tab=admin");
    await page.waitForLoadState("networkidle");
    await expect(page).not.toHaveURL(/index\.html/);
  });

  test("users hierarchy page renders for admin accounts", async ({ page }) => {
    test.skip(process.env.IZZY_TEST_IS_ADMIN !== "true", "Set IZZY_TEST_IS_ADMIN=true to validate admin-only users hierarchy.");
    await page.goto("/users.html");
    await page.waitForLoadState("networkidle");
    await expect(page.getByText(/arbol de jerarquia/i)).toBeVisible();
    await expect(page.locator("#treeRenderMode")).toBeVisible();
    await expect(page.locator("#treeViewMode")).toBeVisible();
  });
});
