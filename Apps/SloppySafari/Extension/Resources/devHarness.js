const demoWidgetHTML = `
  <!doctype html>
  <html>
  <head>
    <style>
      body {
        margin: 0;
        font: 700 18px -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
        color: #f4f4f4;
        background: linear-gradient(135deg, #2f343b, #191b1f);
      }
      main {
        display: grid;
        height: 100vh;
        box-sizing: border-box;
        padding: 18px;
        align-content: center;
        gap: 6px;
      }
      span {
        color: rgba(244, 244, 244, 0.62);
        font-size: 13px;
      }
    </style>
  </head>
  <body>
    <main>
      <strong>Widget draft</strong>
      <span>Сделай мне виджет погоды, чтобы я мог смотреть погоду на 3 дня вперед</span>
    </main>
  </body>
  </html>
`;

const demoSettings = {
  coreURLString: "http://127.0.0.1:25101",
  authToken: "",
  defaultAgentID: "sloppy",
  startPageEnabled: true,
  startPageTheme: "dark",
  startPageItems: [
    {
      id: "shortcut-vk-small",
      kind: "shortcut",
      title: "vk",
      url: "https://vk.com/",
      colSpan: 1,
      rowSpan: 2,
      order: 0
    },
    {
      id: "widget-weather",
      kind: "widget",
      artifactId: "widget-weather",
      title: "Widget draft",
      size: "medium",
      colSpan: 2,
      rowSpan: 2,
      order: 1
    },
    {
      id: "shortcut-vk-wide",
      kind: "shortcut",
      title: "vk.com",
      url: "https://vk.com/",
      colSpan: 1,
      rowSpan: 2,
      order: 2
    },
    {
      id: "shortcut-vk-1",
      kind: "shortcut",
      title: "vk.com",
      url: "https://vk.com/",
      colSpan: 1,
      rowSpan: 1,
      order: 3
    },
    {
      id: "shortcut-vk-2",
      kind: "shortcut",
      title: "vk.com",
      url: "https://vk.com/",
      colSpan: 1,
      rowSpan: 1,
      order: 4
    },
    {
      id: "shortcut-vk-3",
      kind: "shortcut",
      title: "vk.com",
      url: "https://vk.com/",
      colSpan: 1,
      rowSpan: 1,
      order: 5
    }
  ],
  startPageShortcuts: [
    { title: "vk", url: "https://vk.com/" },
    { title: "vk.com", url: "https://vk.com/" }
  ],
  floatingButtonEnabled: false,
  selectionBubbleEnabled: false,
  mesh: { enabled: false }
};

const demoArtifacts = [
  {
    id: "widget-weather",
    title: "Widget draft",
    kind: "widget",
    size: "medium",
    widget: { size: "medium" }
  }
];

const delay = (value) => new Promise((resolve) => {
  window.setTimeout(() => resolve(value), 20);
});

globalThis.chrome = {
  runtime: {
    getURL(path) {
      const assetPath = String(path || "").trim();
      if (assetPath.startsWith("/")) {
        return assetPath;
      }
      if (/^[a-z0-9.-]+\.svg$/i.test(assetPath) && assetPath !== "so_logo.svg") {
        return `/icons/${assetPath}`;
      }
      return `/${assetPath}`;
    },
    onMessage: {
      addListener() {}
    },
    async sendMessage(message = {}) {
      if (message.type === "sloppy.settings.get") {
        return delay(structuredClone(demoSettings));
      }
      if (message.type === "sloppy.settings.save") {
        Object.assign(demoSettings, structuredClone(message.settings || {}));
        return delay(structuredClone(demoSettings));
      }
      if (message.type === "sloppy.artifacts.list") {
        return delay({ artifacts: structuredClone(demoArtifacts) });
      }
      if (message.type === "sloppy.artifacts.widget") {
        return delay({
          artifactId: message.artifactId || "widget-weather",
          title: "Widget draft",
          size: "medium",
          width: 320,
          height: 180,
          html: demoWidgetHTML
        });
      }
      if (message.type === "sloppy.artifacts.widget.generate") {
        return delay({
          artifact: {
            id: `widget-${Date.now()}`,
            title: message.prompt || "Generated widget",
            kind: "widget",
            size: message.size || "medium",
            widget: { size: message.size || "medium" }
          }
        });
      }
      if (message.type === "sloppy.bookmarks.list") {
        return delay([
          { id: "vk", title: "vk.com", url: "https://vk.com/" },
          { id: "github", title: "GitHub", url: "https://github.com/" }
        ]);
      }
      if (message.type === "sloppy.agents.list") {
        return delay({ agents: [{ id: "sloppy", name: "Sloppy" }] });
      }
      if (message.type === "sloppy.models.list") {
        return delay({ models: [] });
      }
      if (message.type === "sloppy.tabs.list") {
        return delay({ tabs: [] });
      }
      if (message.type === "sloppy.slashCommands.list") {
        return delay({ commands: [] });
      }
      if (message.type === "sloppy.voice.config.get") {
        return delay({ enabled: false });
      }
      return delay({});
    }
  }
};

window.addEventListener("load", () => {
  if (new URLSearchParams(window.location.search).get("customize") === "0") {
    return;
  }
  window.setTimeout(() => {
    document.querySelector("[data-sloppy-customize]")?.click();
  }, 120);
});
