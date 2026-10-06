// Local-only Playwright config (does not touch playwright.config.js / production).
// Usage: npx playwright test -c playwright.local.config.js
const { defineConfig, devices } = require("@playwright/test");

module.exports = defineConfig({
  testDir: "./tests/local",
  outputDir: "./test-results-local",
  timeout: 30_000,
  reporter: [["list"]],
  use: { baseURL: "http://127.0.0.1:4173" },
  webServer: {
    command: "python3 -m http.server 4173 --bind 127.0.0.1",
    url: "http://127.0.0.1:4173/tutorial-crecimiento.html",
    reuseExistingServer: false,
    timeout: 20_000,
  },
  projects: [{ name: "chromium", use: { ...devices["Desktop Chrome"] } }],
});
