export const DASHBOARD_THEME_STORAGE_KEY = "sloppy_dashboard_theme";
export const DASHBOARD_ACCENT_STORAGE_KEY = "sloppy_accent_color";

export const DASHBOARD_THEMES = [
  {
    id: "brutalist",
    name: "Brutalist",
    description: "The original high-contrast terminal aesthetic.",
    colorScheme: "dark",
    defaultAccent: "#ccff00",
    preview: ["#000000", "#111111", "#ccff00"]
  },
  {
    id: "modern",
    name: "Modern",
    description: "A calm, layered workspace with softer depth and motion.",
    colorScheme: "dark",
    defaultAccent: "#8b9dff",
    preview: ["#0b0d12", "#171a22", "#8b9dff"]
  }
] as const;

export type DashboardThemeId = (typeof DASHBOARD_THEMES)[number]["id"];
export type DashboardTheme = (typeof DASHBOARD_THEMES)[number];

export const DEFAULT_DASHBOARD_THEME: DashboardThemeId = "brutalist";

export function isDashboardThemeId(value: unknown): value is DashboardThemeId {
  return DASHBOARD_THEMES.some((theme) => theme.id === value);
}

export function resolveDashboardTheme(value: unknown): DashboardThemeId {
  return isDashboardThemeId(value) ? value : DEFAULT_DASHBOARD_THEME;
}

export function getDashboardTheme(themeId: DashboardThemeId): DashboardTheme {
  return DASHBOARD_THEMES.find((theme) => theme.id === themeId) ?? DASHBOARD_THEMES[0];
}

export function loadDashboardTheme(): DashboardThemeId {
  try {
    const storedTheme = window.localStorage.getItem(DASHBOARD_THEME_STORAGE_KEY);
    if (isDashboardThemeId(storedTheme)) {
      return storedTheme;
    }
  } catch {
    // Fall back to the deploy-time client configuration when storage is unavailable.
  }

  return resolveDashboardTheme(window.__SLOPPY_CONFIG__?.theme);
}

export function applyDashboardTheme(themeId: DashboardThemeId) {
  const theme = getDashboardTheme(themeId);
  document.documentElement.dataset.theme = theme.id;
  document.documentElement.style.colorScheme = theme.colorScheme;
}

export function persistDashboardTheme(themeId: DashboardThemeId) {
  try {
    window.localStorage.setItem(DASHBOARD_THEME_STORAGE_KEY, themeId);
  } catch {
    // The applied theme remains active for the current page session.
  }
  applyDashboardTheme(themeId);
}

export function isValidAccentColor(value: unknown): value is string {
  return (
    typeof value === "string" &&
    value.trim().length > 0 &&
    typeof window.CSS !== "undefined" &&
    window.CSS.supports("color", value.trim())
  );
}

export function resolveDashboardAccent(themeId: DashboardThemeId): string {
  try {
    const storedAccent = window.localStorage.getItem(DASHBOARD_ACCENT_STORAGE_KEY);
    if (isValidAccentColor(storedAccent)) {
      return storedAccent.trim();
    }
  } catch {
    // Continue with the deploy-time or theme default accent.
  }

  const configuredAccent = window.__SLOPPY_CONFIG__?.accentColor;
  return isValidAccentColor(configuredAccent)
    ? configuredAccent.trim()
    : getDashboardTheme(themeId).defaultAccent;
}

export function applyDashboardAccent(color: string) {
  if (!isValidAccentColor(color)) {
    return;
  }

  const normalized = color.trim();
  document.documentElement.style.setProperty("--accent-color", normalized);
  document.documentElement.style.setProperty(
    "--accent-opacity-bg",
    `color-mix(in srgb, ${normalized} 59%, transparent)`
  );
}

export function initializeDashboardAppearance() {
  const themeId = loadDashboardTheme();
  applyDashboardTheme(themeId);
  applyDashboardAccent(resolveDashboardAccent(themeId));
  return themeId;
}
