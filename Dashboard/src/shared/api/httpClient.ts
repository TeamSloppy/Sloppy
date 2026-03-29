import { emitNotification } from "../../features/notifications/notificationBus";

type HttpMethod = "GET" | "POST" | "PUT" | "PATCH" | "DELETE";

interface JsonRequestOptions<TBody = unknown> {
  path: string;
  method?: HttpMethod;
  body?: TBody;
  signal?: AbortSignal;
  headers?: HeadersInit;
}

export interface JsonResponse<TData> {
  ok: boolean;
  status: number;
  data: TData | null;
}

export const API_BASE_OVERRIDE_STORAGE_KEY = "sloppy_api_base_override";
const DEFAULT_API_BASE = "http://localhost:25101";

export function normalizeApiBaseInput(value: string) {
  const trimmed = value.trim();
  if (!trimmed) {
    return "";
  }

  const withProtocol = /^[a-zA-Z][a-zA-Z\d+\-.]*:\/\//.test(trimmed) ? trimmed : `http://${trimmed}`;

  try {
    const url = new URL(withProtocol);
    if (!/^https?:$/.test(url.protocol) || !url.hostname || url.username || url.password || url.pathname !== "/" || url.search || url.hash) {
      return "";
    }
    return url.toString().replace(/\/+$/, "");
  } catch {
    return "";
  }
}

export function getStoredApiBaseOverride() {
  try {
    const stored = window.localStorage.getItem(API_BASE_OVERRIDE_STORAGE_KEY);
    if (typeof stored !== "string") {
      return "";
    }
    return normalizeApiBaseInput(stored);
  } catch {
    return "";
  }
}

export function setStoredApiBaseOverride(value: string) {
  try {
    const normalized = normalizeApiBaseInput(value);
    if (!normalized) {
      window.localStorage.removeItem(API_BASE_OVERRIDE_STORAGE_KEY);
      return "";
    }
    window.localStorage.setItem(API_BASE_OVERRIDE_STORAGE_KEY, normalized);
    return normalized;
  } catch {
    return "";
  }
}

export function resolveApiBase() {
  const storedOverride = getStoredApiBaseOverride();
  if (storedOverride) {
    return storedOverride;
  }

  const configured = window.__SLOPPY_CONFIG__?.apiBase;
  if (typeof configured === "string" && configured.trim().length > 0) {
    return normalizeApiBaseInput(configured) || configured.trim().replace(/\/+$/, "");
  }

  const envConfigured = import.meta.env.VITE_API_BASE;
  if (typeof envConfigured === "string" && envConfigured.trim().length > 0) {
    return normalizeApiBaseInput(envConfigured) || envConfigured.trim().replace(/\/+$/, "");
  }

  return DEFAULT_API_BASE;
}

export function buildApiURL(path: string) {
  const base = resolveApiBase();
  const normalizedPath = path.startsWith("/") ? path : `/${path}`;
  return `${base}${normalizedPath}`;
}

export function buildWebSocketURL(path: string) {
  const apiURL = new URL(buildApiURL(path));
  apiURL.protocol = apiURL.protocol === "https:" ? "wss:" : "ws:";
  return apiURL.toString();
}

async function parseJSONSafely<TData>(response: Response): Promise<TData | null> {
  try {
    return (await response.json()) as TData;
  } catch {
    return null;
  }
}

export async function requestJson<TResponse, TBody = unknown>(
  options: JsonRequestOptions<TBody>
): Promise<JsonResponse<TResponse>> {
  const headers = new Headers(options.headers ?? undefined);
  const hasBody = options.body !== undefined;
  const method = options.method ?? (hasBody ? "POST" : "GET");

  if (hasBody && !headers.has("content-type")) {
    headers.set("content-type", "application/json");
  }

  const requestInit: RequestInit = {
    method,
    signal: options.signal
  };

  requestInit.headers = headers;

  if (hasBody) {
    requestInit.body = JSON.stringify(options.body);
  }

  try {
    const response = await fetch(buildApiURL(options.path), requestInit);
    const data = await parseJSONSafely<TResponse>(response);
    return { ok: response.ok, status: response.status, data };
  } catch {
    emitNetworkError();
    return { ok: false, status: 0, data: null };
  }
}

let lastNetworkErrorTs = 0;
const NETWORK_ERROR_THROTTLE_MS = 10_000;

function emitNetworkError() {
  const now = Date.now();
  if (now - lastNetworkErrorTs < NETWORK_ERROR_THROTTLE_MS) return;
  lastNetworkErrorTs = now;
  emitNotification("system_error", "Connection lost", "Failed to reach the backend. Check if Sloppy is running.");
}
