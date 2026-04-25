export const DASHBOARD_AUTH_TOKEN_STORAGE_KEY = "sloppy_dashboard_auth_token";
export const DASHBOARD_AUTH_INVALIDATED_EVENT = "sloppy-dashboard-auth-invalidated";

let inMemoryDashboardAuthToken = loadStoredDashboardAuthToken();

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

export function setDashboardAuthToken(token: string, options?: { persist?: boolean }) {
  const normalized = normalizeDashboardAuthToken(token);
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

export function invalidateDashboardAuthToken() {
  clearDashboardAuthToken({ notify: true });
}
