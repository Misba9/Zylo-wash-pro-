import type { Page } from "@playwright/test";

const IGNORE = [
  /favicon/i,
  /Download the React DevTools/i,
  /\[HMR\]/i,
  /Failed to load resource: the server responded with a status of 404/i,
  /React does not recognize the .* prop on a DOM element/i,
];

export function attachConsoleGuard(page: Page) {
  const errors: string[] = [];
  page.on("pageerror", (err) => errors.push(`pageerror: ${err.message}`));
  page.on("console", (msg) => {
    if (msg.type() !== "error") return;
    const text = msg.text();
    if (IGNORE.some((re) => re.test(text))) return;
    errors.push(`console: ${text}`);
  });
  return {
    assertClean: () => {
      if (errors.length) {
        throw new Error(`Browser errors:\n${errors.slice(0, 8).join("\n")}`);
      }
    },
    errors: () => [...errors],
  };
}
