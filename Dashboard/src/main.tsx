import React from "react";
import { createRoot } from "react-dom/client";
import { App } from "./App";
import { ErrorBoundary } from "./components/ErrorBoundary/ErrorBoundary";
import "./styles.css";

const configuredAccentColor = window.__SLOPPY_CONFIG__?.accentColor;
if (
  typeof configuredAccentColor === "string" &&
  configuredAccentColor.trim().length > 0 &&
  typeof window.CSS !== "undefined" &&
  window.CSS.supports("color", configuredAccentColor.trim())
) {
  document.documentElement.style.setProperty("--accent-color", configuredAccentColor.trim());
}

const rootElement = document.getElementById("root");
if (!rootElement) {
  throw new Error("Root element #root was not found");
}

createRoot(rootElement).render(
  <React.StrictMode>
    <ErrorBoundary>
      <App />
    </ErrorBoundary>
  </React.StrictMode>
);
