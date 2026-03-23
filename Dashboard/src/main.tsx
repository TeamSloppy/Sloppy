import React from "react";
import { createRoot } from "react-dom/client";
import { App } from "./App";
import { ErrorBoundary } from "./components/ErrorBoundary/ErrorBoundary";
import "./styles/index.css";

const storedAccentColor = localStorage.getItem("sloppy_accent_color");
const resolvedAccentColor = storedAccentColor || window.__SLOPPY_CONFIG__?.accentColor;
if (
  typeof resolvedAccentColor === "string" &&
  resolvedAccentColor.trim().length > 0 &&
  typeof window.CSS !== "undefined" &&
  window.CSS.supports("color", resolvedAccentColor.trim())
) {
  const color = resolvedAccentColor.trim();
  document.documentElement.style.setProperty("--accent-color", color);
  document.documentElement.style.setProperty("--accent-opacity-bg", color + "97");
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
