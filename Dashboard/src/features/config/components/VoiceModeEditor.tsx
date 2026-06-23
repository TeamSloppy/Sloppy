import React from "react";

const OPENAI_VOICES = ["alloy", "ash", "ballad", "coral", "echo", "fable", "marin", "nova", "onyx", "sage", "shimmer", "verse"];

function ChoiceGroup({ label, value, options, onChange, columns = 2 }) {
  return (
    <div className="config-voice-field">
      <span>{label}</span>
      <div className={`provider-auth-mode-segmented config-segmented config-voice-segmented ${columns === 3 ? "is-three" : ""}`} role="tablist" aria-label={label}>
        {options.map((option) => (
          <button
            key={option.value}
            type="button"
            className={value === option.value ? "active" : ""}
            onClick={() => onChange(option.value)}
          >
            {option.label}
          </button>
        ))}
      </div>
    </div>
  );
}

function ToggleField({ id, title, description = "", checked, onChange }) {
  return (
    <label className="config-voice-toggle" htmlFor={id}>
      <span className="config-voice-toggle-copy">
        <strong>{title}</strong>
        {description ? <small>{description}</small> : null}
      </span>
      <span className="agent-tools-switch">
        <input id={id} type="checkbox" checked={checked} onChange={(event) => onChange(event.target.checked)} />
        <span className="agent-tools-switch-track" />
      </span>
    </label>
  );
}

function TextField({ id, label, value, onChange, hint = "", wide = false }) {
  return (
    <label className={`config-voice-field ${wide ? "config-voice-field-wide" : ""}`} htmlFor={id}>
      <span>{label}</span>
      <input id={id} value={value} onChange={(event) => onChange(event.target.value)} />
      {hint ? <small>{hint}</small> : null}
    </label>
  );
}

function SliderField({ id, label, value, min, max, step, onChange }) {
  const numericValue = Number.isFinite(Number(value)) ? Number(value) : 1;

  return (
    <label className="config-voice-field config-voice-slider" htmlFor={id}>
      <span>
        {label}
        <strong>{numericValue.toFixed(1)}</strong>
      </span>
      <input
        id={id}
        type="range"
        min={min}
        max={max}
        step={step}
        value={numericValue}
        onChange={(event) => onChange(Number(event.target.value))}
      />
    </label>
  );
}

export function VoiceModeEditor({ voiceMode, onUpdate }) {
  const provider = voiceMode?.provider || "auto";
  const input = voiceMode?.input || {};
  const openAI = voiceMode?.openAI || {};
  const local = voiceMode?.local || {};
  const isEnabled = Boolean(voiceMode?.enabled);
  const providerLabel = provider === "openai" ? "OpenAI" : provider === "local" ? "Local" : "Auto";
  const inputModeLabel = input.mode === "auto_submit" ? "Auto submit" : "Push to talk";

  function update(patch) {
    onUpdate?.({ ...voiceMode, ...patch });
  }

  function updateInput(patch) {
    update({ input: { ...input, ...patch } });
  }

  function updateOpenAI(patch) {
    update({ openAI: { ...openAI, ...patch } });
  }

  function updateLocal(patch) {
    update({ local: { ...local, ...patch } });
  }

  return (
    <div className="config-voice-shell">
      <section className="config-voice-hero" aria-labelledby="voice-mode-title">
        <div className="config-voice-hero-copy">
          <span className={`config-voice-status ${isEnabled ? "is-on" : "is-off"}`}>{isEnabled ? "Enabled" : "Disabled"}</span>
          <h3 id="voice-mode-title">Voice Mode</h3>
          <p>Speak to the agent from Dashboard and Safari. Auto prefers OpenAI audio when configured, with local browser speech as the fallback.</p>
        </div>
        <div className="config-voice-summary">
          <div>
            <span>Provider</span>
            <strong>{providerLabel}</strong>
          </div>
          <div>
            <span>Input</span>
            <strong>{inputModeLabel}</strong>
          </div>
          <ToggleField
            id="voice-mode-enabled"
            title="Voice mode"
            description="Turns microphone workflows on or off."
            checked={isEnabled}
            onChange={(checked) => update({ enabled: checked })}
          />
        </div>
      </section>

      <section className="config-voice-panel" aria-labelledby="voice-routing-title">
        <div className="config-voice-panel-head">
          <div>
            <span className="entry-editor-kicker">Routing</span>
            <h4 id="voice-routing-title">How voice is handled</h4>
          </div>
        </div>
        <div className="config-voice-two-column">
          <ChoiceGroup
            label="Provider"
            value={provider}
            columns={3}
            options={[
              { value: "auto", label: "Auto" },
              { value: "openai", label: "OpenAI" },
              { value: "local", label: "Local" }
            ]}
            onChange={(value) => update({ provider: value })}
          />
          <ChoiceGroup
            label="Input mode"
            value={input.mode || "push_to_talk"}
            options={[
              { value: "push_to_talk", label: "Push to talk" },
              { value: "auto_submit", label: "Auto submit" }
            ]}
            onChange={(value) => updateInput({ mode: value })}
          />
          <TextField
            id="voice-mode-language"
            label="Language"
            value={input.language || "auto"}
            hint="Use auto, en-US, ru-RU, or any browser/OpenAI language code."
            onChange={(value) => updateInput({ language: value })}
          />
          <ToggleField
            id="voice-preview-before-send"
            title="Preview before send"
            description="Review recognized text before it goes to the agent."
            checked={input.previewBeforeSend !== false}
            onChange={(checked) => updateInput({ previewBeforeSend: checked })}
          />
        </div>
      </section>

      <div className="config-voice-columns">
        <section className="config-voice-panel" aria-labelledby="voice-openai-title">
          <div className="config-voice-panel-head">
            <div>
              <span className="entry-editor-kicker">OpenAI</span>
              <h4 id="voice-openai-title">Agent voice</h4>
            </div>
            <ToggleField
              id="voice-openai-enabled"
              title="Use OpenAI"
              checked={Boolean(openAI.enabled)}
              onChange={(checked) => updateOpenAI({ enabled: checked })}
            />
          </div>
          <div className="config-voice-form">
            <TextField
              id="voice-transcription-model"
              label="Transcription model"
              value={openAI.transcriptionModel || ""}
              onChange={(value) => updateOpenAI({ transcriptionModel: value })}
            />
            <TextField
              id="voice-tts-model"
              label="TTS model"
              value={openAI.ttsModel || ""}
              onChange={(value) => updateOpenAI({ ttsModel: value })}
            />
            <TextField
              id="voice-openai-voice"
              label="Voice"
              value={openAI.voice || "coral"}
              onChange={(value) => updateOpenAI({ voice: value })}
            />
            <div className="config-voice-field config-voice-field-wide">
              <span>Quick voice picker</span>
              <div className="actor-team-search-wrap config-voice-choice-list">
                {OPENAI_VOICES.map((voice) => (
                  <button
                    key={voice}
                    type="button"
                    className={`actor-team-search-option ${(openAI.voice || "coral") === voice ? "active" : ""}`}
                    onClick={() => updateOpenAI({ voice })}
                  >
                    {voice}
                  </button>
                ))}
              </div>
            </div>
            <label className="config-voice-field config-voice-field-wide" htmlFor="voice-openai-instructions">
              <span>Voice instructions</span>
              <textarea
                id="voice-openai-instructions"
                value={openAI.instructions || ""}
                onChange={(event) => updateOpenAI({ instructions: event.target.value })}
              />
              <small>Tone and speaking style for generated audio.</small>
            </label>
          </div>
        </section>

        <section className="config-voice-panel" aria-labelledby="voice-local-title">
          <div className="config-voice-panel-head">
            <div>
              <span className="entry-editor-kicker">Local</span>
              <h4 id="voice-local-title">Browser fallback</h4>
            </div>
            <ToggleField
              id="voice-local-enabled"
              title="Use local"
              checked={local.enabled !== false}
              onChange={(checked) => updateLocal({ enabled: checked })}
            />
          </div>
          <div className="config-voice-form">
            <TextField
              id="voice-local-name"
              label="Voice name"
              value={local.voiceName || ""}
              hint="Leave empty for the browser default."
              wide
              onChange={(value) => updateLocal({ voiceName: value })}
            />
            <SliderField
              id="voice-local-rate"
              label="Rate"
              min="0.5"
              max="2"
              step="0.1"
              value={local.rate ?? 1}
              onChange={(value) => updateLocal({ rate: value })}
            />
            <SliderField
              id="voice-local-pitch"
              label="Pitch"
              min="0"
              max="2"
              step="0.1"
              value={local.pitch ?? 1}
              onChange={(value) => updateLocal({ pitch: value })}
            />
          </div>
        </section>
      </div>
    </div>
  );
}
