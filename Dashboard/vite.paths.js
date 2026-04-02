import path from "node:path";
import { fileURLToPath } from "node:url";

export function resolveDashboardPaths(configURL = import.meta.url) {
  const dashboardDir = path.dirname(fileURLToPath(configURL));

  return {
    dashboardDir,
    packageJsonPath: path.resolve(dashboardDir, "package.json"),
    dashboardConfigPath: path.resolve(dashboardDir, "config.json"),
    distDir: path.resolve(dashboardDir, "dist"),
  };
}
