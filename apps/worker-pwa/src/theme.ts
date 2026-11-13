export type ThemeMode = "light" | "dark";

const KEY = "zylo_field_theme";

export function preferTheme(): ThemeMode {
  try {
    const saved = localStorage.getItem(KEY) as ThemeMode | null;
    if (saved === "light" || saved === "dark") return saved;
  } catch { /* ignore */ }
  return window.matchMedia?.("(prefers-color-scheme: dark)").matches ? "dark" : "light";
}

export function applyTheme(mode: ThemeMode) {
  document.documentElement.setAttribute("data-theme", mode);
  const meta = document.querySelector('meta[name="theme-color"]');
  if (meta) meta.setAttribute("content", mode === "dark" ? "#0C1A16" : "#123F36");
  try { localStorage.setItem(KEY, mode); } catch { /* ignore */ }
}

export function toggleTheme(current: ThemeMode): ThemeMode {
  const next = current === "dark" ? "light" : "dark";
  applyTheme(next);
  return next;
}
