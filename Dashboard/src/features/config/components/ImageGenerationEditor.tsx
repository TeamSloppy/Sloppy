import React, { useEffect, useRef } from "react";

const FALLBACK_MODELS = [
  { id: "fal-ai/flux-2", title: "FLUX 2", provider: "fal", supportsEditing: true, maxReferenceImages: 4 },
  { id: "fal-ai/flux-2-pro", title: "FLUX 2 Pro", provider: "fal", supportsEditing: true, maxReferenceImages: 4 },
  { id: "gpt-image-2", title: "GPT Image 2", provider: "openai", supportsEditing: true, maxReferenceImages: 16 },
  { id: "gpt-image-2", title: "GPT Image 2", provider: "codex", supportsEditing: true, maxReferenceImages: 16 }
];

export function ImageGenerationEditor({ draftConfig, status, mutateDraft, openProviders }) {
  const config = draftConfig.imageGeneration || {};
  const providerMenu = useRef<HTMLDetailsElement>(null);
  useEffect(() => {
    const dismiss = (event: PointerEvent) => {
      const menu = providerMenu.current;
      if (menu?.open && event.target instanceof Node && !menu.contains(event.target)) menu.open = false;
    };
    document.addEventListener("pointerdown", dismiss);
    return () => document.removeEventListener("pointerdown", dismiss);
  }, []);
  const providers = [
    { id: "followAgent", label: "Follow agent", model: "gpt-image-2" },
    { id: "codex", label: "Codex", model: "gpt-image-2" },
    { id: "openai", label: "OpenAI API", model: "gpt-image-2" },
    { id: "fal", label: "FAL", model: "fal-ai/flux-2" }
  ];
  const selected = providers.find((option) => option.id === config.provider) || providers[3];
  const provider = selected.id;
  const catalog = Array.isArray(status?.models) && status.models.length > 0 ? status.models : FALLBACK_MODELS;
  const models = catalog.filter((model) => String(model.provider || "fal") === provider);
  const activeModel = String(config.model || selected.model);
  const providerTitle = selected.label;
  const providerStatus = String(status?.provider || "fal") === provider ? status : null;
  const credentialLabel = providerStatus?.hasEnvironmentKey
    ? `Using ${provider === "openai" ? "OPENAI_API_KEY" : "FAL_KEY"} from the Sloppy environment.`
    : providerStatus?.hasConfiguredKey
      ? provider === "openai" ? "Using the API key from the OpenAI API provider settings." : "Using the API key stored in runtime config."
      : provider === "openai" ? "Set OPENAI_API_KEY or configure an OpenAI API provider key." : "Set FAL_KEY or save a FAL API key below.";

  return (
    <div className="providers-shell">
      <section className="entry-editor-card providers-intro-card">
        <h3>Image Generation</h3>
        <p className="placeholder-text">
          Choose how agents generate and edit images with <code>images.generate</code>.
        </p>
        <label className="config-voice-toggle" htmlFor="image-generation-enabled">
          <span className="config-voice-toggle-copy">
            <strong>Enable paid image generation</strong>
            <small>Agents can generate or edit one image per tool call when enabled.</small>
          </span>
          <span className="agent-tools-switch">
            <input
              id="image-generation-enabled"
              type="checkbox"
              checked={Boolean(config.enabled)}
              onChange={(event) => mutateDraft((draft) => {
                draft.imageGeneration.enabled = event.target.checked;
              })}
            />
            <span className="agent-tools-switch-track" />
          </span>
        </label>
        <div className="config-voice-field config-voice-field-wide">
          <span id="image-provider-label">Provider</span>
          <details
            className="actor-team-search-wrap config-image-provider-picker"
            ref={providerMenu}
            onBlur={(event) => {
              if (event.relatedTarget && !event.currentTarget.contains(event.relatedTarget)) event.currentTarget.open = false;
            }}
            onKeyDown={(event) => {
              if (!event.currentTarget.open) return;
              if (event.key === "Escape") {
                event.currentTarget.open = false;
                event.currentTarget.querySelector("summary")?.focus();
                event.stopPropagation();
              } else if (["ArrowUp", "ArrowDown", "Home", "End"].includes(event.key)) {
                const options = Array.from(event.currentTarget.querySelectorAll<HTMLButtonElement>("button[role=menuitemradio]"));
                const current = options.indexOf(document.activeElement as HTMLButtonElement);
                const index = event.key === "Home" ? 0
                  : event.key === "End" || (current < 0 && event.key === "ArrowUp") ? options.length - 1
                    : (current + (event.key === "ArrowDown" ? 1 : -1) + options.length) % options.length;
                event.preventDefault();
                options[index]?.focus();
              }
            }}
          >
            <summary className="actor-team-search" aria-labelledby="image-provider-label image-provider-value">
              <span id="image-provider-value">{providerTitle}</span>
            </summary>
            <div className="actor-team-dropdown" role="menu" aria-labelledby="image-provider-label">
              {providers.map((option) => (
                <button
                  key={option.id}
                  type="button"
                  role="menuitemradio"
                  aria-checked={provider === option.id}
                  className={`actor-team-search-option ${provider === option.id ? "active" : ""}`}
                  onClick={(event) => {
                    const details = event.currentTarget.closest("details");
                    mutateDraft((draft) => {
                      draft.imageGeneration.provider = option.id;
                      draft.imageGeneration.model = option.model;
                    });
                    if (details) {
                      details.open = false;
                      details.querySelector("summary")?.focus();
                    }
                  }}
                >
                  {option.label}
                </button>
              ))}
            </div>
          </details>
        </div>
      </section>

      <section className="provider-card configured">
        <div className="provider-list-main">
          <div className="provider-card-head">
            <h4>{providerTitle}</h4>
            {provider !== "codex" && provider !== "followAgent" && (
              <span className={`provider-state ${providerStatus?.hasAnyKey ? "on" : "off"}`}>
                {providerStatus?.hasEnvironmentKey ? "env" : providerStatus?.hasConfiguredKey ? "configured" : "not set"}
              </span>
            )}
          </div>
          <p>{{
            followAgent: "Uses Codex or OpenAI API according to the current agent turn. Choose a provider explicitly for other agents.",
            codex: status?.hasCodexConnection ? "Uses the connected ChatGPT account." : "Connect Codex under Settings → Providers.",
            openai: "OpenAI Images API with GPT Image generation and multi-reference editing.",
            fal: "Native FAL queue API with text-to-image and multi-reference editing."
          }[provider]}</p>

          <div className="entry-form-grid" style={{ marginTop: 16 }}>
            {provider !== "followAgent" && <div style={{ gridColumn: "1 / -1" }}>
              <span className="entry-form-label">Model</span>
              <div className="actor-team-search-wrap config-image-model-list" role="listbox" aria-label="Image generation model">
                {models.map((model) => (
                  <button
                    key={model.id}
                    type="button"
                    role="option"
                    aria-selected={activeModel === model.id}
                    className={`actor-team-search-option ${activeModel === model.id ? "active" : ""}`}
                    onClick={() => mutateDraft((draft) => {
                      draft.imageGeneration.model = model.id;
                    })}
                  >
                    <strong>{model.title || model.id}</strong>
                    <small>{model.supportsEditing ? `Generate + edit · ${model.maxReferenceImages || 4} references` : "Generate only"}</small>
                  </button>
                ))}
              </div>
            </div>}

            {provider === "codex" && !status?.hasCodexConnection && (
              <div style={{ gridColumn: "1 / -1" }}>
                <button type="button" onClick={openProviders}>Open provider settings</button>
              </div>
            )}
            {provider === "fal" ? <label style={{ gridColumn: "1 / -1" }}>
              API Key
              <input
                type="password"
                autoComplete="new-password"
                value={String(config.fal?.apiKey || "")}
                placeholder="FAL key"
                onChange={(event) => mutateDraft((draft) => {
                  draft.imageGeneration.fal.apiKey = event.target.value;
                })}
              />
              <span className="entry-form-hint">{credentialLabel}</span>
            </label> : provider === "openai" ? (
              <div style={{ gridColumn: "1 / -1" }} className="entry-form-hint">
                {credentialLabel} Configure the key under <strong>Providers → OpenAI API</strong>.
              </div>
            ) : null}

            <label>
              Timeout (ms)
              <input
                type="number"
                min="10000"
                max="600000"
                step="1000"
                value={Number(config.timeoutMs || 180000)}
                onChange={(event) => mutateDraft((draft) => {
                  draft.imageGeneration.timeoutMs = Math.min(600000, Math.max(10000, Number(event.target.value) || 180000));
                })}
              />
            </label>
          </div>
        </div>
      </section>
    </div>
  );
}
