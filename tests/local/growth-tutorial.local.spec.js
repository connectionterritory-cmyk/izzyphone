const { test, expect } = require("@playwright/test");

const widths = [375, 768, 1024, 1440];

for (const width of widths) {
  test.describe(`tutorial-crecimiento @${width}px`, () => {
    test.use({ viewport: { width, height: 900 } });

    test("renders all sections, no overflow, no JS errors", async ({ page }, info) => {
      const errors = [];
      page.on("pageerror", (e) => errors.push(e.message));
      page.on("console", (m) => m.type() === "error" && !/fonts\.g|ERR_/.test(m.text()) && errors.push(m.text()));
      await page.goto("/tutorial-crecimiento.html");

      // hero + path
      await expect(page.locator("h1")).toContainText("IZZY");
      await expect(page.locator(".hero .quote")).toContainText("Crece con tu producción");
      await expect(page.locator(".path .lvl")).toHaveCount(3);
      await expect(page.getByText("APRENDE → PRODUCE → CRECE").first()).toBeVisible();

      // tables: 10 rows each, tabs switch
      await expect(page.locator('#panel-train tbody tr')).toHaveCount(10);
      await page.getByRole("tab", { name: "Asociado" }).click();
      await expect(page.locator("#panel-assoc")).toBeVisible();
      await expect(page.locator("#panel-train")).toBeHidden();
      await expect(page.locator('#panel-assoc tbody tr')).toHaveCount(10);
      await page.getByRole("tab", { name: "Supervisor" }).click();
      await expect(page.locator('#panel-sup tbody tr')).toHaveCount(10);

      // accordions
      const det = page.locator("details").first();
      await expect(det).toHaveAttribute("open", "");
      await det.locator("summary").click();
      await expect(det).not.toHaveAttribute("open", "");
      await det.locator("summary").click();
      await expect(det).toHaveAttribute("open", "");
      await expect(page.locator('table[data-table="bonus-25-49"] tbody tr')).toHaveCount(10);
      await expect(page.locator('table[data-table="bonus-50-plus"] tbody tr')).toHaveCount(10);

      // leadership, maintenance, chargeback
      await expect(page.locator("#liderazgo .scen")).toHaveCount(2);
      await expect(page.locator("#liderazgo .scen .node")).toHaveCount(6);
      await expect(page.locator('#liderazgo [data-leadership="eligible"]')).toHaveCount(8);
      await expect(page.locator('#liderazgo [data-leadership="not-eligible"]')).toHaveCount(2);
      await expect(page.locator("#liderazgo .elig").getByText("AT&T Air", { exact: true })).toBeVisible();
      await expect(page.locator("#liderazgo")).toContainText("No generan Bono de Liderazgo para ti");
      await expect(page.locator("#liderazgo")).toContainText("Cada conexión puede generar un solo Bono de Liderazgo");
      await expect(page.locator("#liderazgo")).toContainText("A gana $0");
      await expect(page.locator("#liderazgo")).not.toContainText(/tu Supervisor directo|pendiente|no está definida/i);
      await expect(page.locator("#mantenimiento")).toContainText("150");
      await expect(page.locator("#chargeback")).toContainText("100%");
      await expect(page.locator("#chargeback")).toContainText("saldo negativo");

      // no horizontal overflow
      const o = await page.evaluate(() => ({
        sw: document.documentElement.scrollWidth,
        iw: innerWidth,
        bad: [...document.querySelectorAll("body *")].filter((e) => {
          const r = e.getBoundingClientRect();
          return r.width && !e.closest(".skip") && (r.right > innerWidth + 1 || r.left < -1);
        }).length,
      }));
      expect(o.sw).toBeLessThanOrEqual(o.iw);
      expect(o.bad).toBe(0);

      if (width === 375 || width === 1440) {
        await page.screenshot({ path: `test-results-local/growth-${width}.png`, fullPage: true });
      }
      expect(errors).toEqual([]);
    });

    test("keyboard navigation", async ({ page }) => {
      await page.goto("/tutorial-crecimiento.html");
      const train = page.getByRole("tab", { name: "Entrenamiento" });
      await train.focus();
      await page.keyboard.press("ArrowRight");
      await expect(page.getByRole("tab", { name: "Asociado" })).toBeFocused();
      await expect(page.locator("#panel-assoc")).toBeVisible();
      await page.keyboard.press("End");
      await expect(page.getByRole("tab", { name: "Supervisor" })).toHaveAttribute("aria-selected", "true");
      await page.keyboard.press("Home");
      await expect(train).toHaveAttribute("aria-selected", "true");
      // accordion via keyboard
      const sum = page.locator("details summary").first();
      await sum.focus();
      await page.keyboard.press("Enter");
      await expect(page.locator("details").first()).not.toHaveAttribute("open", "");
      // skip link is first tab stop
      await page.goto("/tutorial-crecimiento.html");
      await page.keyboard.press("Tab");
      await expect(page.locator(".skip")).toBeFocused();
    });
  });
}
