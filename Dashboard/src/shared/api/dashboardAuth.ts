export const DASHBOARD_AUTH_TOKEN_STORAGE_KEY = "sloppy_dashboard_auth_token";
export const DASHBOARD_AUTH_REMEMBER_STORAGE_KEY = "sloppy_dashboard_auth_remember";
export const DASHBOARD_AUTH_INVALIDATED_EVENT = "sloppy-dashboard-auth-invalidated";

let inMemoryDashboardAuthToken = loadStoredDashboardAuthToken();
let dashboardAuthRevision = 0;

export interface DashboardAuthSnapshot {
  token: string;
  revision: number;
}

export function captureDashboardAuth(): DashboardAuthSnapshot {
  return { token: getDashboardAuthToken(), revision: dashboardAuthRevision };
}

function normalizeDashboardAuthToken(value: string | null | undefined) {
  return typeof value === "string" ? value.trim() : "";
}

function loadStoredDashboardAuthToken() {
  try {
    return normalizeDashboardAuthToken(window.localStorage.getItem(DASHBOARD_AUTH_TOKEN_STORAGE_KEY));
  } catch {
    return "";
  }
}

export function getDashboardAuthToken() {
  if (inMemoryDashboardAuthToken) {
    return inMemoryDashboardAuthToken;
  }
  inMemoryDashboardAuthToken = loadStoredDashboardAuthToken();
  return inMemoryDashboardAuthToken;
}

export function hasStoredDashboardAuthToken() {
  return loadStoredDashboardAuthToken().length > 0;
}

export function isDashboardAuthTokenPersisted() {
  return hasStoredDashboardAuthToken();
}

export function getDashboardAuthRememberPreference() {
  try {
    return window.localStorage.getItem(DASHBOARD_AUTH_REMEMBER_STORAGE_KEY) !== "false";
  } catch {
    return true;
  }
}

export function setDashboardAuthRememberPreference(remember: boolean) {
  try {
    window.localStorage.setItem(DASHBOARD_AUTH_REMEMBER_STORAGE_KEY, String(remember));
  } catch {
    // Ignore localStorage failures and keep the current in-memory UI state.
  }
}

export function setDashboardAuthToken(token: string, options?: { persist?: boolean }) {
  const normalized = normalizeDashboardAuthToken(token);
  dashboardAuthRevision += 1;
  inMemoryDashboardAuthToken = normalized;

  try {
    if (normalized && options?.persist) {
      window.localStorage.setItem(DASHBOARD_AUTH_TOKEN_STORAGE_KEY, normalized);
    } else {
      window.localStorage.removeItem(DASHBOARD_AUTH_TOKEN_STORAGE_KEY);
    }
  } catch {
    // Ignore localStorage failures and keep the in-memory token for this session.
  }

  return normalized;
}

export function clearDashboardAuthToken(options?: { notify?: boolean }) {
  dashboardAuthRevision += 1;
  inMemoryDashboardAuthToken = "";
  try {
    window.localStorage.removeItem(DASHBOARD_AUTH_TOKEN_STORAGE_KEY);
  } catch {
    // Ignore localStorage failures.
  }

  if (options?.notify) {
    window.dispatchEvent(new CustomEvent(DASHBOARD_AUTH_INVALIDATED_EVENT));
  }
}

// A rejected in-flight request only owns the session it was sent with. A later
// login (including re-entering the same legacy token) must survive its response.
export function invalidateDashboardAuthToken(rejected: DashboardAuthSnapshot) {
  if (!rejected.token || rejected.revision !== dashboardAuthRevision || rejected.token !== getDashboardAuthToken()) {
    return;
  }
  clearDashboardAuthToken({ notify: true });
}
