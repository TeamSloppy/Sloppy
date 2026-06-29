(function attachSloppySettingsPanel(globalThis) {
  const sectionIDs = ["connection", "mesh", "interface"];

  function renderSettingsDialog({ t, escapeHTML, icon }) {
    return `
      <dialog class="sloppy-settings-dialog" data-sloppy-settings-dialog>
        <form method="dialog" class="sloppy-settings-card sloppy-settings-layout">
          <div class="sloppy-settings-sidebar">
            <header class="sloppy-settings-sidebar-header">
              <strong>Settings</strong>
            </header>
            <nav class="sloppy-settings-nav" data-sloppy-settings-nav aria-label="Settings sections">
              <button class="sloppy-settings-nav-item" type="button" data-sloppy-settings-nav-item="connection">Connection</button>
              <button class="sloppy-settings-nav-item" type="button" data-sloppy-settings-nav-item="mesh">Mesh</button>
              <button class="sloppy-settings-nav-item" type="button" data-sloppy-settings-nav-item="interface">Interface</button>
            </nav>
          </div>
          <div class="sloppy-settings-main">
            <header class="sloppy-settings-main-header">
              <div>
                <strong data-sloppy-settings-title>Connection</strong>
                <p class="sloppy-settings-note">Choose how the extension connects to Sloppy.</p>
              </div>
              <button class="sloppy-icon-button" value="cancel" aria-label="${escapeHTML(t("closeSettings"))}">${icon("close")}</button>
            </header>

            <section class="sloppy-settings-pane" data-sloppy-settings-section="connection">
              <div class="sloppy-settings-group">
                <label>Core URL<input data-sloppy-core-url placeholder="http://127.0.0.1:25101"></label>
                <label>Auth token<input data-sloppy-auth-token type="password" autocomplete="off"></label>
                <label>Default agent<input data-sloppy-default-agent placeholder="sloppy"></label>
              </div>
              <div class="sloppy-settings-actions">
                <a class="sloppy-settings-link" href="https://sloppy.team" target="_blank" rel="noreferrer">${escapeHTML(t("downloadSloppy"))}</a>
              </div>
            </section>

            <section class="sloppy-settings-pane" data-sloppy-settings-section="mesh" hidden>
              <div class="sloppy-settings-group">
                <label class="sloppy-settings-toggle">
                  <input data-sloppy-mesh-enabled type="checkbox">
                  <span>Use mesh relay</span>
                </label>
                <label>Invite token<textarea data-sloppy-mesh-invite rows="4"></textarea></label>
                <label>Target node<input data-sloppy-mesh-target-node></label>
                <p class="sloppy-settings-note" data-sloppy-mesh-status>Mesh is not configured.</p>
              </div>
              <div class="sloppy-settings-actions">
                <button class="sloppy-settings-save sloppy-settings-secondary-action" type="button" data-sloppy-mesh-join>Join mesh</button>
              </div>
            </section>

            <section class="sloppy-settings-pane" data-sloppy-settings-section="interface" hidden>
              <div class="sloppy-settings-group">
                <label class="sloppy-settings-toggle">
                  <input data-sloppy-floating-button type="checkbox">
                  <span>Show floating button</span>
                </label>
                <label class="sloppy-settings-toggle">
                  <input data-sloppy-selection-bubble-enabled type="checkbox">
                  <span>Show selection bubble</span>
                </label>
              </div>
            </section>

            <footer class="sloppy-settings-footer">
              <button class="sloppy-settings-save" type="button" data-sloppy-save-settings>Save settings</button>
            </footer>
          </div>
        </form>
      </dialog>
    `;
  }

  function setActiveSection(frame, sectionID) {
    const resolvedID = sectionIDs.includes(sectionID) ? sectionID : "connection";
    const title = frame.querySelector("[data-sloppy-settings-title]");
    if (title) {
      title.textContent = resolvedID.charAt(0).toUpperCase() + resolvedID.slice(1);
    }
    sectionIDs.forEach((id) => {
      const navItem = frame.querySelector(`[data-sloppy-settings-nav-item="${id}"]`);
      const section = frame.querySelector(`[data-sloppy-settings-section="${id}"]`);
      const isActive = id === resolvedID;
      navItem?.classList?.toggle?.("is-active", isActive);
      navItem?.setAttribute?.("aria-current", isActive ? "page" : "false");
      if (section) {
        section.hidden = !isActive;
      }
    });
  }

  function wireSettingsNavigation(frame) {
    sectionIDs.forEach((id) => {
      frame.querySelector(`[data-sloppy-settings-nav-item="${id}"]`)?.addEventListener("click", () => {
        setActiveSection(frame, id);
      });
    });
  }

  function wireMeshJoin(frame, dependencies) {
    frame.querySelector("[data-sloppy-mesh-join]")?.addEventListener("click", async () => {
      const token = frame.querySelector("[data-sloppy-mesh-invite]").value;
      const status = frame.querySelector("[data-sloppy-mesh-status]");
      status.textContent = "Joining mesh...";
      try {
        const response = await dependencies.sendMessage({ type: "sloppy.mesh.join", token });
        if (response?.error) {
          status.textContent = response.error;
          return;
        }
        const mesh = response?.mesh || {};
        const state = dependencies.getState();
        state.settings = {
          ...(state.settings || {}),
          mesh
        };
        frame.querySelector("[data-sloppy-mesh-enabled]").checked = Boolean(mesh.enabled);
        frame.querySelector("[data-sloppy-mesh-target-node]").value = mesh.targetNodeId || "";
        status.textContent = dependencies.meshStatusText(mesh);
      } catch (error) {
        status.textContent = error?.message || "Unable to join mesh.";
      }
    });
  }

  function openSettings(frame, dependencies) {
    const state = dependencies.getState();
    const mesh = state.settings?.mesh || { enabled: false };
    frame.querySelector("[data-sloppy-core-url]").value = state.settings?.coreURLString || "";
    frame.querySelector("[data-sloppy-auth-token]").value = state.settings?.authToken || "";
    frame.querySelector("[data-sloppy-default-agent]").value = state.settings?.defaultAgentID || "sloppy";
    frame.querySelector("[data-sloppy-mesh-enabled]").checked = Boolean(mesh.enabled);
    frame.querySelector("[data-sloppy-mesh-invite]").value = "";
    frame.querySelector("[data-sloppy-mesh-target-node]").value = mesh.targetNodeId || "";
    frame.querySelector("[data-sloppy-mesh-status]").textContent = dependencies.meshStatusText(mesh);
    frame.querySelector("[data-sloppy-floating-button]").checked = Boolean(state.settings?.floatingButtonEnabled);
    frame.querySelector("[data-sloppy-selection-bubble-enabled]").checked = dependencies.selectionBubbleEnabled();
    setActiveSection(frame, "connection");
    dependencies.openPanelDialog(frame.querySelector("[data-sloppy-settings-dialog]"));
  }

  async function saveSettings(frame, dependencies) {
    const state = dependencies.getState();
    const settings = {
      coreURLString: frame.querySelector("[data-sloppy-core-url]").value,
      authToken: frame.querySelector("[data-sloppy-auth-token]").value,
      defaultAgentID: frame.querySelector("[data-sloppy-default-agent]").value,
      selectedModel: state.settings?.selectedModel || "",
      voiceLanguage: dependencies.normalizeVoiceLanguage(state.settings?.voiceLanguage),
      voiceInputDeviceId: dependencies.normalizeVoiceInputDeviceId(state.settings?.voiceInputDeviceId),
      sessionId: state.settings?.sessionId || null,
      mesh: {
        ...(state.settings?.mesh || {}),
        enabled: frame.querySelector("[data-sloppy-mesh-enabled]").checked,
        targetNodeId: frame.querySelector("[data-sloppy-mesh-target-node]").value
      },
      floatingButtonEnabled: frame.querySelector("[data-sloppy-floating-button]").checked,
      selectionBubbleEnabled: frame.querySelector("[data-sloppy-selection-bubble-enabled]").checked,
      startPageEnabled: state.settings?.startPageEnabled !== false,
      startPageTheme: state.settings?.startPageTheme || "dark",
      startPageBackgroundImage: state.settings?.startPageBackgroundImage || "",
      startPageShortcuts: dependencies.startPageShortcutItems(state.settings),
      startPageItems: state.settings?.startPageItems || []
    };
    state.settings = await dependencies.sendMessage({ type: "sloppy.settings.save", settings });
    frame.querySelector("[data-sloppy-settings-dialog]").close();
    await dependencies.loadAgents(frame);
    await dependencies.loadModels(frame);
    dependencies.render(frame);
    dependencies.renderFloatingButton();
    if (!dependencies.selectionBubbleEnabled()) {
      dependencies.hideSelectionMenu();
    } else {
      dependencies.scheduleSelectionMenuUpdate();
    }
  }

  function wire(frame, dependencies) {
    wireSettingsNavigation(frame);
    wireMeshJoin(frame, dependencies);
  }

  globalThis.SloppySettingsPanel = {
    renderSettingsDialog,
    wire,
    openSettings,
    saveSettings,
    setActiveSection
  };
})(globalThis);
