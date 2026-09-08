import { readFile } from "node:fs/promises";
import assert from "node:assert/strict";
import vm from "node:vm";
import { transformSync } from "esbuild";
const source = await readFile("src/analytics.ts", "utf8");
function setup(scriptUrl, preferences = {}, dev = false) {
  const scripts = [];
  const context = {
    exports: {},
    module: { exports: {} },
    URL,
    window: {},
    navigator: preferences,
    document: {
      createElement: () => ({}),
      head: { append: (s) => scripts.push(s) },
    },
  };
  context.exports = context.module.exports;
  const { code } = transformSync(source, {
    loader: "ts",
    format: "cjs",
    define: {
      "import.meta.env.VITE_PLAUSIBLE_SCRIPT_URL": JSON.stringify(scriptUrl),
      "import.meta.env.DEV": String(dev),
    },
  });
  vm.runInNewContext(code, context);
  return { api: context.module.exports, context, scripts };
}
for (const [url, preferences, dev] of [
  ["", {}, false],
  ["https://plausible.io/js/test.js", { doNotTrack: "1" }, false],
  ["https://plausible.io/js/test.js", { globalPrivacyControl: true }, false],
  ["http://example.com/tracker.js", {}, false],
  ["https://plausible.io/js/test.js", {}, true],
]) {
  const fixture = setup(url, preferences, dev);
  fixture.api.initializeAnalytics();
  fixture.api.track("Waitlist submit");
  assert.equal(fixture.scripts.length, 0);
}
const fixture = setup("https://plausible.io/js/test.js");
fixture.api.initializeAnalytics();
assert.equal(fixture.scripts.length, 1);
fixture.api.track("Waitlist success");
assert.equal(fixture.context.window.plausible.q[0][0], "Waitlist success");
fixture.scripts[0].onerror();
fixture.api.track("Waitlist error");
assert.equal(fixture.context.window.plausible.q.length, 1);
console.log(
  "Analytics checks passed: opt-in configuration, DNT/GPC, localhost, HTTPS, event queue, and graceful script failure. No network requests made.",
);
