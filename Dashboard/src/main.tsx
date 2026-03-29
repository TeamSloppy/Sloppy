import React from "react";
import { createRoot } from "react-dom/client";
import { App } from "./App";
import { ErrorBoundary } from "./components/ErrorBoundary/ErrorBoundary";
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

function applyAccentColor() {
  const storedAccentColor = localStorage.getItem("sloppy_accent_color");
  const resolvedAccentColor = storedAccentColor || window.__SLOPPY_CONFIG__?.accentColor;
  if (
    typeof resolvedAccentColor !== "string" ||
    resolvedAccentColor.trim().length === 0 ||
    typeof window.CSS === "undefined" ||
    !window.CSS.supports("color", resolvedAccentColor.trim())
  ) {
    return;
  }

  const color = resolvedAccentColor.trim();
  document.documentElement.style.setProperty("--accent-color", color);
  document.documentElement.style.setProperty("--accent-opacity-bg", color + "97");
}

async function bootstrap() {
  await loadClientConfig();
  applyAccentColor();

  createRoot(rootElement).render(
    <React.StrictMode>
      <ErrorBoundary>
        <App />
      </ErrorBoundary>
    </React.StrictMode>
  );
}

void bootstrap();
