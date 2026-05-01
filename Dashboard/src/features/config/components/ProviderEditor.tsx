import React, { useEffect, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { Gemini, ProviderIcon } from "@lobehub/icons";

/** ProviderIcon resolves providers via keyword map; "gemini" is not registered (only "google"). */
function ProviderBrandMark({ brandProviderKey, size }) {
  if (!brandProviderKey) {
    return (
      <span className="material-symbols-rounded" aria-hidden="true" style={{ fontSize: size, lineHeight: 1 }}>
        hub
      </span>
    );
  }
  if (brandProviderKey === "gemini") {
    return <Gemini.Color size={size} />;
  }
  return <ProviderIcon provider={brandProviderKey} size={size} type="color" />;
}

export function ProviderEditor({
  providerCatalog,
  configuredProviderRows,
  customModelsCount,
  openAIProviderStatus,
  anthropicProviderStatus,
  providerModalMeta,
  providerForm,
  providerModelStatus,
  providerModelOptions,
  providerModelMenuOpen,
  providerModelMenuRect,
  providerModelPickerRef,
  providerModelMenuRef,
  modalActiveEntry,
  onOpenProviderAtIndex,
  onAppendProvider,
  onSetProviderRowDisabled,
  onCloseProviderModal,
  onUpdateProviderForm,
  onOpenOAuth,
  onOpenAnthropicOAuth,
  onImportAnthropicClaudeCredentials,
  onDisconnectAnthropicOAuth,
  onCancelDeviceCode,
  onCopyDeviceCode,
  onOpenDeviceCodeLoginPage,
  deviceCode,
  deviceCodeCopied,
  isDeviceCodePolling,
  onRemoveProvider,
  onSaveProvider,
  onTestProviderConnection,
  providerProbeTesting,
  onSetProviderModelMenuOpen,
  onSetProviderModelMenuRect,
  providerIsConfigured,
  filterProviderModels
}) {
  const [addMenuOpen, setAddMenuOpen] = useState(false);
  const addMenuRef = useRef(null);

  useEffect(() => {
    if (!addMenuOpen) {
      return undefined;
    }
    function handlePointerDown(event) {
      if (addMenuRef.current && !addMenuRef.current.contains(event.target)) {
        setAddMenuOpen(false);
      }
    }
    window.addEventListener("pointerdown", handlePointerDown);
    return () => window.removeEventListener("pointerdown", handlePointerDown);
  }, [addMenuOpen]);

  const activeProviderStatus = providerModalMeta ? providerModelStatus[providerModalMeta.id] : "";
  const activeProviderModels = providerModalMeta ? providerModelOptions[providerModalMeta.id] || [] : [];
  const filteredProviderModels = filterProviderModels(activeProviderModels, providerForm?.model);
  const isTestingActiveProvider = providerModalMeta
    ? Boolean(providerProbeTesting?.[providerModalMeta.id])
    : false;
  const canTestActiveProvider = Boolean(
    providerModalMeta &&
      providerModalMeta.id !== "openai-oauth" &&
      providerModalMeta.supportsModelCatalog &&
      onTestProviderConnection
  );

  return (
    <div className="providers-shell">
      <section className="entry-editor-card providers-intro-card">
        <h3>LLM Providers</h3>
        <p className="placeholder-text">
          Configure credentials and endpoints for providers. At least one enabled provider is required for agents.
          Disabled providers stay in config but are ignored at runtime.
        </p>
        <div className="providers-note">
          Provider changes save automatically. Add credentials, choose a model, and run a connection test when needed.
        </div>
        {customModelsCount > 0 ? (
          <p className="placeholder-text">
            Config has {customModelsCount} custom model entries. They are preserved and available in raw mode.
          </p>
        ) : null}
      </section>

      <div className="providers-section-toolbar">
        <div className="providers-section-toolbar-spacer" />
        <div className="providers-toolbar-actions" ref={addMenuRef}>
          <button
            type="button"
            className="provider-card-action providers-toolbar-btn"
            onClick={() => setAddMenuOpen((o) => !o)}
            aria-expanded={addMenuOpen}
            aria-haspopup="listbox"
          >
            Add provider
            <span className="material-symbols-rounded" style={{ fontSize: "1.1rem", marginLeft: 4 }} aria-hidden>
              expand_more
            </span>
          </button>
          {addMenuOpen ? (
            <div className="providers-dropdown" role="listbox">
              {providerCatalog.map((p) => (
                <button
                  key={p.id}
                  type="button"
                  role="option"
                  className="providers-dropdown-item"
                  onClick={() => {
                    onAppendProvider(p.id);
                    setAddMenuOpen(false);
                  }}
                >
                  <span className="providers-dropdown-item-title">{p.title}</span>
                  <span className="providers-dropdown-item-desc">{p.description}</span>
                </button>
              ))}
            </div>
          ) : null}
        </div>
      </div>

      <details className="providers-presets-details">
        <summary className="providers-presets-summary">
          <span className="material-symbols-rounded providers-presets-icon" aria-hidden>
            apps
          </span>
          Standard provider presets
        </summary>
        <p className="placeholder-text providers-presets-hint">
          Quick reference — use <strong>Add provider</strong> above to create a new row. Click a preset to add that type.
        </p>
        <section className="providers-list providers-presets-grid">
          {providerCatalog.map((provider) => (
            <div key={provider.id} className="provider-card provider-preset-card">
              <span className="provider-list-icon" aria-hidden="true">
                <ProviderBrandMark brandProviderKey={provider.brandProviderKey} size={30} />
              </span>
              <div className="provider-list-main">
                <div className="provider-card-head">
                  <h4>{provider.title}</h4>
                </div>
                <p>{provider.description}</p>
                <span className="provider-model-line">Default: {provider.modelHint}</span>
              </div>
              <button
                type="button"
                className="provider-card-action"
                onClick={() => onAppendProvider(provider.id)}
              >
                Add
              </button>
            </div>
          ))}
        </section>
      </details>

      <section className="providers-configured-block">
        <h4 className="providers-configured-heading">Configured providers</h4>
        <div className="providers-list">
          {configuredProviderRows.length === 0 ? (
            <p className="placeholder-text">No provider rows yet. Use Add provider or a preset.</p>
          ) : (
            configuredProviderRows.map((row) => {
              const { index, entry, catalogId, meta } = row;
              const label = meta?.title || catalogId || "Custom";
              const configuredViaEnvironment =
                catalogId === "openai-api" &&
                openAIProviderStatus.hasEnvironmentKey &&
                !Boolean(String(entry?.apiKey || "").trim()) &&
                Boolean(String(entry?.model || "").trim()) &&
                Boolean(String(entry?.apiUrl || "").trim());
              const configuredViaOAuth =
                catalogId === "openai-oauth" &&
                openAIProviderStatus.hasOAuthCredentials &&
                Boolean(String(entry?.model || "").trim()) &&
                Boolean(String(entry?.apiUrl || "").trim());
              const configuredViaAnthropicOAuth =
                catalogId === "anthropic-oauth" &&
                (anthropicProviderStatus.hasOAuthCredentials || Boolean(String(entry?.apiKey || "").trim())) &&
                Boolean(String(entry?.model || "").trim()) &&
                Boolean(String(entry?.apiUrl || "").trim());
              let configured = false;
              if (configuredViaEnvironment || configuredViaOAuth || configuredViaAnthropicOAuth) {
                configured = true;
              } else if (meta && catalogId !== "openai-oauth") {
                configured = providerIsConfigured(meta, entry);
              }
              const configuredBadgeText =
                configuredViaEnvironment ? "env" : configuredViaOAuth || configuredViaAnthropicOAuth ? "oauth" : configured ? "configured" : "not set";

              return (
                <div
                  key={`${index}-${catalogId || "custom"}`}
                  className={`provider-instance-row ${entry.disabled ? "provider-instance-row--disabled" : ""}`}
                >
                  <div className="provider-instance-row-main">
                    <span className="provider-list-icon" aria-hidden="true">
                      {meta?.brandProviderKey ? (
                        <ProviderBrandMark brandProviderKey={meta.brandProviderKey} size={28} />
                      ) : (
                        <span className="material-symbols-rounded" style={{ fontSize: 28 }}>
                          hub
                        </span>
                      )}
                    </span>
                    <div className="provider-list-main">
                      <div className="provider-card-head">
                        <h4>{entry.title || label}</h4>
                        <span className={`provider-state ${configured ? "on" : "off"}`}>{configuredBadgeText}</span>
                        {entry.disabled ? (
                          <span className="provider-disabled-badge">disabled</span>
                        ) : null}
                      </div>
                      <span className="provider-model-line">
                        {label}
                        {catalogId ? ` · ${catalogId}` : ""}
                      </span>
                      <span className="provider-model-line">
                        Model: {entry.model || "—"} · {String(entry.apiUrl || "").slice(0, 56)}
                        {String(entry.apiUrl || "").length > 56 ? "…" : ""}
                      </span>
                    </div>
                  </div>
                  <label className="provider-instance-toggle">
                    <span className="agent-tools-switch">
                      <input
                        type="checkbox"
                        aria-label="Provider enabled"
                        checked={!entry.disabled}
                        onChange={(e) => onSetProviderRowDisabled(index, !e.target.checked)}
                      />
                      <span className="agent-tools-switch-track" />
                    </span>
                  </label>
                  <button
                    type="button"
                    className="provider-card-action"
                    onClick={() => onOpenProviderAtIndex(index)}
                  >
                    Manage
                  </button>
                </div>
              );
            })
          )}
        </div>
      </section>

      {providerModalMeta && providerForm ? (
        <div className="provider-modal-overlay" onClick={onCloseProviderModal}>
          <section className="provider-modal-card" onClick={(event) => event.stopPropagation()}>
            <div className="provider-modal-head">
              <div className="provider-modal-title-row">
                {providerModalMeta.brandProviderKey ? (
                  <span className="provider-modal-brand" aria-hidden="true">
                    <ProviderBrandMark brandProviderKey={providerModalMeta.brandProviderKey} size={28} />
                  </span>
                ) : null}
                <h3>{providerModalMeta.title}</h3>
              </div>
              <button type="button" className="provider-close-button" onClick={onCloseProviderModal}>
                x
              </button>
            </div>
            <p className="placeholder-text">{providerModalMeta.description}</p>

            <div className="provider-modal-form">
              <label>
                Label
                <input
                  value={providerForm.title ?? ""}
                  onChange={(event) => onUpdateProviderForm("title", event.target.value)}
                  placeholder="Display name in list"
                />
              </label>
              <label className="provider-modal-disabled-row">
                <span className="agent-tools-switch">
                  <input
                    type="checkbox"
                    checked={!providerForm.disabled}
                    onChange={(e) => onUpdateProviderForm("disabled", !e.target.checked)}
                  />
                  <span className="agent-tools-switch-track" />
                </span>
                <span>Enabled (runtime)</span>
              </label>
              {providerModalMeta.requiresApiKey ? (
              <label>
                API Key
                <input
                  type="password"
                  value={providerForm.apiKey}
                  onChange={(event) => onUpdateProviderForm("apiKey", event.target.value)}
                  placeholder={
                    providerModalMeta.id === "anthropic-oauth"
                      ? "Manual setup token fallback (sk-ant-oat…)"
                      : providerModalMeta.id === "anthropic"
                        ? "Console API key (sk-ant-api…)"
                        : "sk-..."
                  }
                />
                {providerModalMeta.id === "openai-api" && openAIProviderStatus.hasEnvironmentKey ? (
                  <span className="placeholder-text">Using OPENAI_API_KEY from Sloppy environment.</span>
                ) : null}
                {providerModalMeta.id === "anthropic-oauth" ? (
                  <span className="placeholder-text">
                    Primary path: Anthropic OAuth or imported Claude Code credentials. Manual token is a fallback.
                  </span>
                ) : null}
              </label>
            ) : null}

              <label>
                API URL
                <input value={providerForm.apiUrl} onChange={(event) => onUpdateProviderForm("apiUrl", event.target.value)} />
              </label>

              <label>
                Model
                <div ref={providerModelPickerRef} className="provider-model-picker">
                  <input
                    value={providerForm.model}
                    onFocus={() => onSetProviderModelMenuOpen(true)}
                    onClick={() => onSetProviderModelMenuOpen(true)}
                    onChange={(event) => onUpdateProviderForm("model", event.target.value)}
                    placeholder="Select model id..."
                  />
                </div>
              </label>
            </div>

            {providerModalMeta.supportsModelCatalog || providerModalMeta.id === "anthropic-oauth" ? (
              <div className="provider-modal-catalog">
                {canTestActiveProvider ? (
                  <div className="provider-modal-probe-row">
                    <button
                      type="button"
                      className="hover-levitate"
                      disabled={isTestingActiveProvider}
                      onClick={() => onTestProviderConnection(providerModalMeta.id)}
                    >
                      {isTestingActiveProvider ? "Testing..." : "Test connection"}
                    </button>
                    <span
                      className={`provider-modal-probe-status ${activeProviderModels.length > 0 ? "ok" : ""}`}
                    >
                      {activeProviderStatus || "Press Test connection to probe the provider."}
                    </span>
                  </div>
                ) : (
                  <p className="placeholder-text">{activeProviderStatus || "Model catalog is loading automatically."}</p>
                )}
                {providerModalMeta.id === "openai-oauth" && deviceCode ? (
                  <div className="provider-device-code-card">
                    <div className="provider-device-code-step">
                      <span className="provider-device-code-step-number">1</span>
                      <span>Copy this device code</span>
                    </div>
                    <div className="provider-device-code-row">
                      <code className="provider-device-code-value">{deviceCode.userCode}</code>
                      <button type="button" onClick={onCopyDeviceCode}>
                        {deviceCodeCopied ? "Copied" : "Copy"}
                      </button>
                    </div>

                    <div className="provider-device-code-step">
                      <span className="provider-device-code-step-number">2</span>
                      <span>Open OpenAI and paste the code</span>
                    </div>
                    <button type="button" onClick={onOpenDeviceCodeLoginPage}>
                      Open login page
                    </button>

                    {isDeviceCodePolling ? (
                      <div className="provider-device-code-waiting">
                        <span className="onboarding-device-code-dot" />
                        <span>Waiting for sign-in confirmation...</span>
                      </div>
                    ) : null}

                    <div className="provider-modal-actions">
                      <button type="button" onClick={onCancelDeviceCode}>Cancel</button>
                      <button type="button" onClick={onOpenOAuth}>Get new code</button>
                    </div>
                  </div>
                ) : providerModalMeta.id === "openai-oauth" ? (
                  <div className="provider-modal-actions">
                    <button type="button" onClick={onOpenOAuth}>
                      {openAIProviderStatus.hasOAuthCredentials ? "Reconnect OpenAI" : "Connect OpenAI"}
                    </button>
                  </div>
                ) : null}
                {providerModalMeta.id === "openai-oauth" && !openAIProviderStatus.hasOAuthCredentials ? (
                  <p className="placeholder-text">
                    You must first <a href="https://chatgpt.com/security-settings" target="_blank" rel="noopener noreferrer">enable device code login</a> in your ChatGPT security settings.
                  </p>
                ) : null}
                {providerModalMeta.id === "openai-oauth" && openAIProviderStatus.hasOAuthCredentials ? (
                  <p className="placeholder-text">
                    Connected
                    {openAIProviderStatus.oauthPlanType ? ` as ${openAIProviderStatus.oauthPlanType}` : ""}
                    {openAIProviderStatus.oauthAccountId ? ` (${openAIProviderStatus.oauthAccountId})` : ""}.
                  </p>
                ) : null}
                {providerModalMeta.id === "anthropic-oauth" ? (
                  <>
                    <div className="provider-modal-actions">
                      <button type="button" onClick={onOpenAnthropicOAuth}>
                        {anthropicProviderStatus.hasOAuthCredentials ? "Reconnect Anthropic" : "Connect Anthropic"}
                      </button>
                      <button type="button" onClick={onImportAnthropicClaudeCredentials}>
                        Import Claude Code credentials
                      </button>
                      {anthropicProviderStatus.hasOAuthCredentials ? (
                        <button type="button" onClick={onDisconnectAnthropicOAuth}>
                          Disconnect
                        </button>
                      ) : null}
                    </div>
                    <p className="placeholder-text">
                      {anthropicProviderStatus.hasOAuthCredentials
                        ? `Connected via ${anthropicProviderStatus.oauthSource || "anthropic_oauth"}${anthropicProviderStatus.oauthRefreshable ? " (refreshable)" : ""}${anthropicProviderStatus.oauthExpiresAt ? `, expires ${anthropicProviderStatus.oauthExpiresAt}` : ""}.`
                        : "Connect Anthropic OAuth or import Claude Code credentials. You can still paste a setup token manually if needed."}
                    </p>
                  </>
                ) : null}
              </div>
            ) : null}
            <div className="provider-modal-footer">
              {modalActiveEntry ? (
                <button type="button" className="danger" onClick={onRemoveProvider}>
                  Remove Provider
                </button>
              ) : (
                <span />
              )}
              <div className="provider-modal-footer-actions">
                <button type="button" onClick={onCloseProviderModal}>
                  Close
                </button>
                <button type="button" onClick={onSaveProvider}>
                  Done
                </button>
              </div>
            </div>
          </section>
        </div>
      ) : null}
      {providerModalMeta && providerForm && providerModelMenuOpen && filteredProviderModels.length > 0 && providerModelMenuRect
        ? createPortal(
          <div
            ref={providerModelMenuRef}
            className="provider-model-picker-menu provider-model-picker-menu-floating"
            style={{
              top: `${providerModelMenuRect.top}px`,
              left: `${providerModelMenuRect.left}px`,
              width: `${providerModelMenuRect.width}px`
            }}
          >
            <div className="provider-model-picker-group">{providerModalMeta.title}</div>
            <div className="provider-model-options" style={{ maxHeight: `${providerModelMenuRect.maxHeight}px` }}>
              {filteredProviderModels.map((model) => (
                <button
                  key={model.id}
                  type="button"
                  className={`provider-model-option ${providerForm.model === model.id ? "active" : ""}`}
                  onMouseDown={(event) => event.preventDefault()}
                  onClick={() => {
                    onUpdateProviderForm("model", model.id);
                    onSetProviderModelMenuOpen(false);
                    onSetProviderModelMenuRect(null);
                  }}
                >
                  <div className="provider-model-option-main">
                    <strong>{model.title || model.id}</strong>
                    {model.contextWindow ? <span className="provider-model-context">{model.contextWindow}</span> : null}
                  </div>
                  <span>{model.id}</span>
                  {Array.isArray(model.capabilities) && model.capabilities.length > 0 ? (
                    <div className="provider-model-capabilities">
                      {model.capabilities.map((capability) => (
                        <span key={`${model.id}-${capability}`}>{capability}</span>
                      ))}
                    </div>
                  ) : null}
                </button>
              ))}
            </div>
          </div>,
          document.body
        )
        : null}
    </div>
  );
}
