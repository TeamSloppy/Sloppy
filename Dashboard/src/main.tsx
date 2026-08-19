import React from "react";
import { createRoot } from "react-dom/client";
import { App } from "./App";
import { markMaterialSymbolsReady } from "./app/iconFont";
import { ErrorBoundary } from "./components/ErrorBoundary/ErrorBoundary";
import { initializeDashboardAppearance } from "./shared/ui/dashboardTheme";
import "./styles/index.css";

const rootElement = document.getElementById("root");
if (!rootElement) {
  throw new Error("Root element #root was not found");
}

async function loadClientConfig() {
  let loadedConfig: SloppyClientConfig = {};

  try {
    const response = await fetch("/config.json", { cache: "no-store" });
    if (response.ok) {
      const payload = await response.json();
      if (payload && typeof payload === "object") {
        loadedConfig = payload as SloppyClientConfig;
      }
    }
  } catch {
    // Keep local defaults when runtime config is unavailable.
  }

  window.__SLOPPY_CONFIG__ = {
    ...loadedConfig,
    ...window.__SLOPPY_CONFIG__
  };
}

async function bootstrap() {
  await loadClientConfig();
  initializeDashboardAppearance();
  void markMaterialSymbolsReady();

  createRoot(rootElement).render(
    <React.StrictMode>
      <ErrorBoundary>
        <App />
      </ErrorBoundary>
    </React.StrictMode>
  );
}

void bootstrap();
