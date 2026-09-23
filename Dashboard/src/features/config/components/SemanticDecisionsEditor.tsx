import React, { useState } from "react";
import { AggregatedModelPicker } from "./AggregatedModelPicker";

const PROVIDERS = [
  { value: "typesafe", label: "TypeSafe direct", description: "Use api.typesafe.ai with a TypeSafe API key." },
  { value: "vercel", label: "Vercel AI Gateway", description: "Use Vercel's TypeSafe-compatible JEV endpoint." }
];

const ROUTING_MODES = [
  { value: "disabled", label: "Disabled", description: "Keep the current Sloppy model-selection flow." },
  { value: "shadow", label: "Shadow", description: "Ask JEV and meter spend, but do not apply its choice." },
  { value: "active", label: "Active", description: "Apply confident JEV choices for automatic turns." }
];

function ChoicePicker({ label, value, options, onChange }) {
  const [open, setOpen] = useState(false);
  const active = options.find((option) => option.value === value) || options[0];
  return (
    <label>
      {label}
      <div className="actor-team-search-wrap">
        <input
          className="actor-team-search"
          value={active.label}
          readOnly
          onFocus={() => setOpen(true)}
          onClick={() => setOpen(true)}
          onBlur={() => setTimeout(() => setOpen(false), 150)}
        />
        {open ? (
          <ul className="actor-team-dropdown">
            {options.map((option) => (
              <li
                key={option.value}
                className={`actor-team-dropdown-item ${option.value === value ? "selected" : ""}`}
                onMouseDown={(event) => {
                  event.preventDefault();
                  onChange(option.value);
                  setOpen(false);
                }}
              >
                <span className="actor-team-dropdown-name">{option.label}</span>
                <span className="actor-team-dropdown-id">{option.description}</span>
                {option.value === value ? <span className="actor-team-dropdown-check">✓</span> : null}
              </li>
            ))}
          </ul>
        ) : null}
      </div>
    </label>
  );
}

function ProfileEditor({ profileId, profile, models, mutateDraft }) {
  const [draftId, setDraftId] = useState(profileId);

  function commitProfileId() {
    const nextId = draftId.trim();
    if (!nextId || nextId === profileId) {
      setDraftId(profileId);
      return;
    }
    mutateDraft((draft) => {
      if (draft.semanticDecisions.modelProfiles[nextId]) return;
      draft.semanticDecisions.modelProfiles[nextId] = draft.semanticDecisions.modelProfiles[profileId];
      delete draft.semanticDecisions.modelProfiles[profileId];
    });
  }

  return (
    <section className="entry-editor-card" style={{ marginTop: 12 }}>
      <div className="entry-list-head">
        <h4>Execution profile</h4>
        <button
          type="button"
          className="config-integration-add-button"
          onClick={() => mutateDraft((draft) => {
            delete draft.semanticDecisions.modelProfiles[profileId];
          })}
        >
          <span className="material-symbols-rounded" aria-hidden>delete</span>
          <span>Remove</span>
        </button>
      </div>
      <div className="entry-form-grid">
        <label>
          Profile ID
          <input value={draftId} onChange={(event) => setDraftId(event.target.value)} onBlur={commitProfileId} />
          <span className="entry-form-hint">Stable choice returned by JEV, for example fast, balanced, or senior.</span>
        </label>
        <AggregatedModelPicker
          label="Executor model"
          value={profile.model || ""}
          onChange={(model) => mutateDraft((draft) => {
            draft.semanticDecisions.modelProfiles[profileId].model = String(model || "");
          })}
          aggregatedModels={models}
        />
        <label style={{ gridColumn: "1 / -1" }}>
          Description for JEV
          <textarea
            rows={3}
            value={profile.description || ""}
            onChange={(event) => mutateDraft((draft) => {
              draft.semanticDecisions.modelProfiles[profileId].description = event.target.value;
            })}
          />
        </label>
      </div>
    </section>
  );
}

export function SemanticDecisionsEditor({
  draftConfig,
  mutateDraft,
  modelCatalog,
  modelCatalogStatus
}) {
  const config = draftConfig.semanticDecisions;
  const provider = config.provider || "typesafe";
  const profiles = Object.entries(config.modelProfiles || {});

  return (
    <div>
      <section className="entry-editor-card">
        <h3>JEV semantic decisions</h3>
        <p className="placeholder-text">
          JEV is optional. Sloppy keeps its existing model selection whenever the provider is unavailable, confidence is low, or routing is disabled.
        </p>
        <div className="entry-form-grid">
          <ChoicePicker
            label="Provider"
            value={provider}
            options={PROVIDERS}
            onChange={(value) => mutateDraft((draft) => {
              draft.semanticDecisions.provider = value;
              if (!draft.semanticDecisions.apiKeyEnvironmentVariable) {
                draft.semanticDecisions.apiKeyEnvironmentVariable = value === "vercel"
                  ? "AI_GATEWAY_API_KEY"
                  : "TYPESAFE_API_KEY";
              }
            })}
          />
          <ChoicePicker
            label="Executor routing"
            value={config.executorModelRouting || "disabled"}
            options={ROUTING_MODES}
            onChange={(value) => mutateDraft((draft) => {
              draft.semanticDecisions.executorModelRouting = value;
            })}
          />
          <label>
            Minimum confidence
            <input
              type="number"
              min="0"
              max="1"
              step="0.01"
              value={String(config.minimumConfidence ?? 0.75)}
              onChange={(event) => mutateDraft((draft) => {
                draft.semanticDecisions.minimumConfidence = Math.min(1, Math.max(0, Number(event.target.value) || 0));
              })}
            />
          </label>
          <label>
            Request timeout (ms)
            <input
              type="number"
              min="100"
              value={String(config.timeoutMs ?? 2000)}
              onChange={(event) => mutateDraft((draft) => {
                draft.semanticDecisions.timeoutMs = Math.max(100, Number.parseInt(event.target.value, 10) || 2000);
              })}
            />
          </label>
          <label>
            Input price per 1M tokens (USD)
            <input
              type="number"
              min="0"
              step="0.001"
              value={String(config.inputCostPerMillionTokensUSD ?? 0.042)}
              onChange={(event) => mutateDraft((draft) => {
                draft.semanticDecisions.inputCostPerMillionTokensUSD = Math.max(0, Number(event.target.value) || 0);
              })}
            />
            <span className="entry-form-hint">Used only when the provider response does not report exact cost.</span>
          </label>
          <label>
            API key environment variable
            <input
              value={config.apiKeyEnvironmentVariable || ""}
              placeholder={provider === "vercel" ? "AI_GATEWAY_API_KEY" : "TYPESAFE_API_KEY"}
              onChange={(event) => mutateDraft((draft) => {
                draft.semanticDecisions.apiKeyEnvironmentVariable = event.target.value;
              })}
            />
          </label>
          <label>
            Custom endpoint (optional)
            <input
              value={config.baseURL || ""}
              placeholder={provider === "vercel"
                ? "https://ai-gateway.vercel.sh/typesafe/v1/systemone"
                : "https://api.typesafe.ai/v1/systemone"}
              onChange={(event) => mutateDraft((draft) => {
                draft.semanticDecisions.baseURL = event.target.value;
              })}
            />
          </label>
          <label>
            JEV model override (optional)
            <input
              value={config.model || ""}
              placeholder={provider === "vercel" ? "typesafe-ai/jev" : "jev-latest"}
              onChange={(event) => mutateDraft((draft) => {
                draft.semanticDecisions.model = event.target.value;
              })}
            />
          </label>
        </div>
      </section>

      <section className="entry-editor-card" style={{ marginTop: 12 }}>
        <h3>API credential</h3>
        <p className="placeholder-text">
          The configured key is stored in the local <code>sloppy.json</code>. Leave it empty to use the environment-variable fallback instead.
        </p>
        <div className="entry-form-grid">
          <label>
            API key
            <input
              type="password"
              autoComplete="new-password"
              value={config.apiKey || ""}
              placeholder="Paste JEV API key"
              onChange={(event) => mutateDraft((draft) => {
                draft.semanticDecisions.apiKey = event.target.value;
              })}
            />
            <span className="entry-form-hint">Config value has priority over the environment variable.</span>
          </label>
        </div>
      </section>

      <section className="entry-editor-card" style={{ marginTop: 12 }}>
        <div className="entry-list-head">
          <div>
            <h3>Executor profiles</h3>
            <p className="placeholder-text">JEV sees only profiles whose models are currently available to the agent. At least two are required.</p>
          </div>
          <button
            type="button"
            className="config-integration-add-button"
            onClick={() => mutateDraft((draft) => {
              const existing = draft.semanticDecisions.modelProfiles || {};
              let index = Object.keys(existing).length + 1;
              let id = `profile-${index}`;
              while (existing[id]) {
                index += 1;
                id = `profile-${index}`;
              }
              existing[id] = { model: "", description: "" };
              draft.semanticDecisions.modelProfiles = existing;
            })}
          >
            <span className="material-symbols-rounded" aria-hidden>add</span>
            <span>Add profile</span>
          </button>
        </div>
        {modelCatalogStatus ? <p className="placeholder-text">{modelCatalogStatus}</p> : null}
        {profiles.length === 0 ? <p className="entry-editor-empty">No executor profiles configured.</p> : null}
      </section>
      {profiles.map(([profileId, profile]) => (
        <ProfileEditor
          key={profileId}
          profileId={profileId}
          profile={profile}
          models={modelCatalog}
          mutateDraft={mutateDraft}
        />
      ))}
    </div>
  );
}
