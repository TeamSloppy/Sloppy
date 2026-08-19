import React from "react";

const FALLBACK_MODELS = [
  { id: "fal-ai/flux-2", title: "FLUX 2", provider: "fal", supportsEditing: true, maxReferenceImages: 4 },
  { id: "fal-ai/flux-2-pro", title: "FLUX 2 Pro", provider: "fal", supportsEditing: true, maxReferenceImages: 4 },
  { id: "gpt-image-2", title: "GPT Image 2", provider: "openai", supportsEditing: true, maxReferenceImages: 16 }
];

export function ImageGenerationEditor({ draftConfig, status, mutateDraft }) {
  const config = draftConfig.imageGeneration || {};
  const provider = String(config.provider || "fal") === "openai" ? "openai" : "fal";
  const catalog = Array.isArray(status?.models) && status.models.length > 0 ? status.models : FALLBACK_MODELS;
  const models = catalog.filter((model) => String(model.provider || "fal") === provider);
  const activeModel = String(config.model || (provider === "openai" ? "gpt-image-2" : "fal-ai/flux-2"));
  const providerTitle = provider === "openai" ? "OpenAI" : "FAL";
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
          Configure the provider used by <code>images.generate</code>. The selected model is controlled here, not by the agent.
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
          <span>Provider</span>
          <div className="provider-auth-mode-segmented config-segmented config-voice-segmented" role="tablist" aria-label="Image generation provider">
            {[
              { id: "fal", label: "FAL", model: "fal-ai/flux-2" },
              { id: "openai", label: "OpenAI", model: "gpt-image-2" }
            ].map((option) => (
              <button
                key={option.id}
                type="button"
                className={provider === option.id ? "active" : ""}
                onClick={() => mutateDraft((draft) => {
                  draft.imageGeneration.provider = option.id;
                  draft.imageGeneration.model = option.model;
                })}
              >
                {option.label}
              </button>
            ))}
          </div>
        </div>
      </section>

      <section className="provider-card configured">
        <div className="provider-list-main">
          <div className="provider-card-head">
            <h4>{providerTitle}</h4>
            <span className={`provider-state ${providerStatus?.hasAnyKey ? "on" : "off"}`}>
              {providerStatus?.hasEnvironmentKey ? "env" : providerStatus?.hasConfiguredKey ? "configured" : "not set"}
            </span>
          </div>
          <p>{provider === "openai"
            ? "OpenAI Images API with GPT Image generation and multi-reference editing."
            : "Native FAL queue API with text-to-image and multi-reference editing."}</p>

          <div className="entry-form-grid" style={{ marginTop: 16 }}>
            <div style={{ gridColumn: "1 / -1" }}>
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
            </div>

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
            </label> : (
              <div style={{ gridColumn: "1 / -1" }} className="entry-form-hint">
                {credentialLabel} Configure the key under <strong>Providers → OpenAI API</strong>.
              </div>
            )}

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
