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
      await expect(page.locator("#tablas-d")).not.toHaveAttribute("open", "");
      await page.locator('#nivel-1 a[href="#tablas"]').click();
      await expect(page.locator("#tablas-d")).toHaveAttribute("open", "");
      await page.getByRole("tab", { name: "Asociado" }).click();
      await expect(page.locator("#panel-assoc")).toBeVisible();
      await expect(page.locator("#panel-train")).toBeHidden();
      await expect(page.locator('#panel-assoc tbody tr')).toHaveCount(10);
      await page.getByRole("tab", { name: "Supervisor" }).click();
      await expect(page.locator('#panel-sup tbody tr')).toHaveCount(10);

      // accordions
      const det = page.locator("#bono-d");
      await expect(det).not.toHaveAttribute("open", "");
      await det.locator("summary").click();
      await expect(det).toHaveAttribute("open", "");
      await det.locator("summary").click();
      await expect(det).not.toHaveAttribute("open", "");
      await det.locator("summary").click();
      await expect(det).toHaveAttribute("open", "");
      await expect(page.locator('table[data-table="bonus-25-49"] tbody tr')).toHaveCount(10);
      await expect(page.locator('table[data-table="bonus-50-plus"] tbody tr')).toHaveCount(10);

      // leadership, maintenance, chargeback
      await expect(page.locator("#liderazgo .scen")).toHaveCount(2);
      await expect(page.locator("#liderazgo .scen .node")).toHaveCount(7);
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

      // beginner-first structure: glossary, 7-step levels, concept -> example -> calculation
      await expect(page.locator("#glosario .g")).toHaveCount(11);
      await expect(page.locator("#glosario .gl-chips li")).toHaveCount(11);
      await expect(page.locator("#glosario .gl-chips")).toBeVisible();
      const wide = (await page.evaluate(() => innerWidth)) >= 768;
      if (wide) await expect(page.locator("#gl-det")).toHaveAttribute("open", ""); else await expect(page.locator("#gl-det")).not.toHaveAttribute("open", "");
      // 10-second level snapshots (level -> AT&T 500 -> amount) and the 100 -> 125 -> 150 staircase
      for (const [kind, name, amount] of [["training", "Agente en Entrenamiento", "$100"], ["associate", "Asociado", "$125"], ["supervisor", "Supervisor", "$150"]]) {
        const sn = page.locator(`.snap[data-snap="${kind}"]`);
        await expect(sn).toBeVisible();
        await expect(sn).toContainText(name);
        await expect(sn).toContainText("AT&T 500 Mbps");
        await expect(sn.locator(".snap-amt")).toHaveText(amount);
        expect(await sn.locator(".snap-amt").evaluate((e) => parseFloat(getComputedStyle(e).fontSize))).toBeGreaterThanOrEqual(46);
      }
      const stairs = page.locator(".stairs");
      await expect(stairs).toBeVisible();
      await expect(stairs.locator(".sb")).toHaveCount(3);
      for (const x of ["$100", "$125", "$150", "+$25"]) await expect(stairs).toContainText(x);
      const barH = await stairs.locator(".sb-bar").evaluateAll((els) => els.map((e) => e.getBoundingClientRect().height));
      expect(barH[0]).toBeLessThan(barH[1]);
      expect(barH[1]).toBeLessThan(barH[2]);
      // scan strips: topic + main number + takeaway
      await expect(page.locator(".scan")).toHaveCount(4);
      for (const [k, num] of [["bono", "+$15"], ["leadership", "$5"], ["maintenance", "150"], ["chargeback", "3 meses"]]) {
        const sc = page.locator(`.scan[data-scan="${k}"]`);
        await sc.scrollIntoViewIfNeeded();
        await expect(sc).toBeVisible();
        await expect(sc).toContainText(num);
        expect(await sc.locator(".scan-n b").first().evaluate((e) => parseFloat(getComputedStyle(e).fontSize))).toBeGreaterThanOrEqual(36);
      }
      await expect(page.locator('.scan[data-scan="bono"]')).toContainText("+$25");
      // progressive disclosure: advanced A/B/C and key rules start closed; the simple María/Carlos case is always visible
      await expect(page.locator("#liderazgo details")).toHaveCount(2);
      await expect(page.locator("#liderazgo .scens")).toBeHidden();
      await expect(page.locator('.ej[data-ej="leadership"]')).toBeVisible();
      await page.locator("#liderazgo details", { hasText: "Ver ejemplo avanzado" }).locator("summary").click();
      await expect(page.locator("#liderazgo .scens")).toBeVisible();
      expect(await page.locator("details").count()).toBeLessThanOrEqual(6);
      // ticket: the result is the dominant element of each level example
      for (const kind of ["level-training", "level-associate", "level-supervisor"]) {
        const card = page.locator(`.ej[data-ej="${kind}"]`);
        await expect(card.locator(".tk")).toBeVisible();
        await expect(card.locator(".tk-who")).toContainText("María vende");
        await expect(card.locator(".tk-res")).toContainText("María genera");
        const fs = await card.locator(".tk-res strong").evaluate((e) => parseFloat(getComputedStyle(e).fontSize));
        expect(fs).toBeGreaterThanOrEqual(52);
      }
      await expect(page.locator('.ej[data-ej="chargeback"] .receipt')).toBeVisible();
      await expect(page.locator('.ej[data-ej="chargeback"] .bigres')).toContainText("-$170");
      await expect(page.locator("#chargeback .stage")).toContainText("Debe permanecer mínimo 3 meses");
      await expect(page.locator("#bono .tramos .tr")).toHaveCount(3);
      for (const a of await page.locator('a[href^="#"]').evaluateAll((els) => els.map((e) => e.getAttribute("href")).filter((h) => h.length > 1))) await expect(page.locator(a)).toHaveCount(1);
      await expect(page.locator("#glosario")).toContainText("Palabras que debes conocer");
      for (const [id, n] of [["nivel-1", 3], ["nivel-2", 3], ["nivel-3", 3]]) {
        await expect(page.locator(`#${id} .q-title`)).toHaveCount(5);
        await expect(page.locator(`#${id} .here .on .you`)).toHaveText("Estás aquí");
        await expect(page.locator(`#${id} .qn`).nth(3)).toHaveText("4–6");
      }
      await expect(page.locator("#nivel-1 .vflow li").filter({ hasText: /\S/ })).toHaveCount(5);
      await expect(page.locator("#pool [data-pool-formula]")).toBeVisible();
      await expect(page.locator("#pool")).toContainText("Tu pool es el grupo de conexiones válidas");
      await expect(page.locator("#liderazgo [data-who], #liderazgo .who")).toBeVisible();
      await expect(page.locator('#liderazgo [data-why="byod"]')).toContainText("solo sobre conexiones de Internet");
      await expect(page.locator('#chargeback [data-explain="chargeback"]')).toContainText("A eso se le llama chargeback");

      // worked examples ("Ejemplo real") — levels are visible without opening any tab
      await expect(page.locator(".ej")).toHaveCount(9);
      const lvl = [
        ["level-training", "1 conexión × $100 = $100", "María es nueva en IZZY Communications"],
        ["level-associate", "1 conexión × $125 = $125", "El producto no cambió. Lo que cambió fue el nivel de María."],
        ["level-supervisor", "1 conexión × $150 = $150", "Ahora puedes ver por qué crecer de nivel cambia tu comisión."],
      ];
      for (const [kind, calc, extra] of lvl) {
        const card = page.locator(`.ej[data-ej="${kind}"]`);
        await card.scrollIntoViewIfNeeded();
        await expect(card).toBeVisible();
        await expect(card.locator(".ej-calc")).toContainText(calc);
        await expect(card).toContainText(extra);
        await expect(card.locator("svg.ic").first()).toBeVisible();
      }
      await expect(page.locator('.ej[data-ej="level-associate"]')).toContainText("+$25");
      await expect(page.locator('.ej[data-ej="level-associate"] .chips3')).toContainText("Misma conexión");
      const fixed = [
        ["bonus-25", ["#24 → $150", "#25 → $150 + $15 = $165", "conexión #25 de tu pool"]],
        ["bonus-50", ["#49 → $150 + $15 = $165", "#50 → $150 + $25 = $175", "No es retroactivo"]],
        ["bonus-spectrum", ["$135 + $10 = $145"]],
        ["leadership", ["3 de Carlos + 2 de su equipo directo elegible = 5 conexiones elegibles", "5 × $5 = $25", "María recibe $25 de Bono de Liderazgo en este ejemplo", "AT&T BYOD: $0 de liderazgo"]],
        ["chargeback", ["$150 + $15 + $5 = $170", "-$170", "compensarse contra comisiones futuras"]],
        ["maintenance", ["60 + 90 = 150", "Meta de mantenimiento cumplida"]],
      ];
      for (const [kind, phrases] of fixed) {
        const card = page.locator(`.ej[data-ej="${kind}"]`);
        await card.scrollIntoViewIfNeeded();
        await expect(card).toBeVisible();
        for (const ph of phrases) await expect(card).toContainText(ph);
        await expect(card.locator("svg.ic").first()).toBeVisible();
        const box = await card.locator("svg.ic").first().boundingBox();
        expect(box.width).toBeGreaterThan(8);
      }
      for (const kind of ["level-training", "level-associate", "level-supervisor", "bonus-25", "bonus-50", "bonus-spectrum", "leadership", "chargeback", "maintenance"]) {
        await expect(page.locator(`.ej[data-ej="${kind}"] .ej-note`).filter({ hasText: "Ejemplo ilustrativo. Las comisiones dependen de conexiones válidas y de las reglas vigentes del plan." })).toHaveCount(1);
      }
      // owner decisions: no 25/50 period, no invented maintenance consequence
      await expect(page.locator("#bono")).not.toContainText(/del mes|mensual|este mes|por trimestre/i);
      await expect(page.locator("#mantenimiento")).not.toContainText(/pierd|pérdida|baja a|gracia|retenci|suspend|penaliz|sanci/i);
      // no card is clipped or wider than the viewport
      const ejBad = await page.evaluate(() => [...document.querySelectorAll(".ej")].filter((e) => { const r = e.getBoundingClientRect(); return r.right > innerWidth + 1 || r.left < -1 || [...e.querySelectorAll("*")].some((x) => !x.classList.contains("sr-only") && x.scrollWidth > x.clientWidth + 1 && getComputedStyle(x).overflowX !== "visible"); }).length);
      expect(ejBad).toBe(0);

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
      // the tables accordion opens from the keyboard
      await page.locator("#tablas-d > summary").focus();
      await page.keyboard.press("Enter");
      await expect(page.locator("#tablas-d")).toHaveAttribute("open", "");
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
      const sum = page.locator("#bono-d > summary");
      await sum.focus();
      await page.keyboard.press("Enter");
      await expect(page.locator("#bono-d")).toHaveAttribute("open", "");
      await page.keyboard.press("Enter");
      await expect(page.locator("#bono-d")).not.toHaveAttribute("open", "");
      // skip link is first tab stop
      await page.goto("/tutorial-crecimiento.html");
      await page.keyboard.press("Tab");
      await expect(page.locator(".skip")).toBeFocused();
    });
  });
}
