import { defineConfig } from "vite";
import fs from "node:fs";
import path from "node:path";

const packageJson = JSON.parse(fs.readFileSync("./package.json", "utf-8"));
const dashboardConfigPath = path.resolve(__dirname, "config.json");

function dashboardConfigPlugin() {
  return {
    name: "dashboard-config-json",
    configureServer(server) {
      server.middlewares.use((req, res, next) => {
        if (req.url !== "/config.json") {
          next();
          return;
        }

        fs.readFile(dashboardConfigPath, "utf-8", (error, content) => {
          if (error) {
            res.statusCode = 404;
            res.end();
            return;
          }

          res.setHeader("Content-Type", "application/json; charset=utf-8");
          res.end(content);
        });
      });
    },
    writeBundle() {
      fs.mkdirSync(path.resolve(__dirname, "dist"), { recursive: true });
      fs.copyFileSync(dashboardConfigPath, path.resolve(__dirname, "dist/config.json"));
    }
  };
}

export default defineConfig({
  plugins: [dashboardConfigPlugin()],
  define: {
    __APP_VERSION__: JSON.stringify(packageJson.version),
  },
  server: {
    port: 25102,
    host: true
  }
});
