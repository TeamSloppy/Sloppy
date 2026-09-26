import React from "react";

const OPENAI_VOICES = ["alloy", "ash", "ballad", "coral", "echo", "fable", "marin", "nova", "onyx", "sage", "shimmer", "verse", "cedar"];
const LEGACY_TTS_VOICES = ["alloy", "ash", "coral", "echo", "fable", "onyx", "nova", "sage", "shimmer"];
const DEFAULT_TTS_MODELS = [
  { id: "gpt-4o-mini-tts", title: "GPT-4o mini TTS" },
  { id: "tts-1", title: "TTS 1" },
  { id: "tts-1-hd", title: "TTS 1 HD" }
];
const DEFAULT_TRANSCRIPTION_MODELS = [
  { id: "gpt-4o-mini-transcribe", title: "GPT-4o mini Transcribe" },
  { id: "gpt-4o-transcribe", title: "GPT-4o Transcribe" },
  { id: "whisper-1", title: "Whisper 1" }
];

function ChoiceGroup({ label, value, options, onChange }) {
  return (
    <div className="config-voice-field">
      <span>{label}</span>
      <div className="provider-auth-mode-segmented config-segmented config-voice-segmented" role="group" aria-label={label}>
        {options.map((option) => (
          <button
            key={option.value}
            type="button"
            className={value === option.value ? "active" : ""}
            aria-pressed={value === option.value}
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

function CapabilityChoiceList({ label, value, options, onSelect, getId = (option) => option.id, getTitle = (option) => option.title || option.id }) {
  if (!options.length) {
    return null;
  }

  return (
    <div className="config-voice-field config-voice-field-wide">
      <span>{label}</span>
      <details className="config-voice-options">
        <summary>Browse available options <span className="material-symbols-rounded" aria-hidden="true">expand_more</span></summary>
        <div className="actor-team-search-wrap config-voice-choice-list">
          {options.map((option) => {
            const id = getId(option);
            const title = getTitle(option);
            return (
              <button
                key={id}
                type="button"
                className={`actor-team-search-option ${value === id ? "active" : ""}`}
                aria-pressed={value === id}
                onClick={(event) => {
                  onSelect(id);
                  event.currentTarget.closest("details")?.removeAttribute("open");
                }}
              >
                {title}
              </button>
            );
          })}
        </div>
      </details>
    </div>
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

export function VoiceModeEditor({ voiceMode, onUpdate, fetchVoiceCapabilities = null }) {
  const [capabilities, setCapabilities] = React.useState(null);
  const [capabilityStatus, setCapabilityStatus] = React.useState(fetchVoiceCapabilities ? "Loading voice options..." : "");
  const provider = voiceMode?.provider || "auto";
  const input = voiceMode?.input || {};
  const openAI = voiceMode?.openAI || {};
  const local = voiceMode?.local || {};
  const isEnabled = Boolean(voiceMode?.enabled);
  const ttsModel = openAI.ttsModel || "gpt-4o-mini-tts";
  const voice = openAI.voice || "coral";
  const speechModels = capabilities?.speechModels?.length ? capabilities.speechModels : DEFAULT_TTS_MODELS;
  const transcriptionModels = capabilities?.transcriptionModels?.length ? capabilities.transcriptionModels : DEFAULT_TRANSCRIPTION_MODELS;
  const voiceOptions = capabilities?.voices?.length
    ? capabilities.voices
    : OPENAI_VOICES.map((id) => ({
        id,
        title: id,
        recommended: id === "marin" || id === "cedar",
        models: LEGACY_TTS_VOICES.includes(id) ? ["gpt-4o-mini-tts", "tts-1", "tts-1-hd"] : ["gpt-4o-mini-tts"]
      }));
  const compatibleVoiceOptions = voiceOptions.filter((option) => !option.models?.length || option.models.includes(ttsModel));
  const displayedVoiceOptions = compatibleVoiceOptions.length ? compatibleVoiceOptions : voiceOptions;

  React.useEffect(() => {
    let cancelled = false;
    if (!fetchVoiceCapabilities || !isEnabled || provider === "local" || !openAI.enabled) {
      setCapabilityStatus("");
      return () => {
        cancelled = true;
      };
    }
    setCapabilityStatus("Loading voice options...");
    fetchVoiceCapabilities()
      .then((nextCapabilities) => {
        if (cancelled) {
          return;
        }
        setCapabilities(nextCapabilities || null);
        setCapabilityStatus(nextCapabilities?.warning || "");
      })
      .catch(() => {
        if (!cancelled) {
          setCapabilityStatus("Unable to load voice options. Built-in defaults are shown.");
        }
      });
    return () => {
      cancelled = true;
    };
  }, [fetchVoiceCapabilities, isEnabled, provider, openAI.enabled]);

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
    <div className="config-voice-shell config-voice-editor">
      <section className="config-voice-intro" aria-labelledby="voice-mode-title">
        <div>
          <span className="config-voice-eyebrow">VOICE</span>
          <h3 id="voice-mode-title">Speak with Sloppy</h3>
          <p>Talk to agents in the dashboard. Choose where speech is processed and how messages are sent.</p>
        </div>
        <ToggleField
          id="voice-mode-enabled"
          title="Voice mode"
          description={isEnabled ? "On" : "Off"}
          checked={isEnabled}
          onChange={(checked) => update({ enabled: checked })}
        />
      </section>

      {!isEnabled ? (
        <p className="config-voice-disabled-note">Turn on Voice Mode to set up the microphone and speech options.</p>
      ) : <>
        <section className="config-voice-section" aria-labelledby="voice-provider-title">
          <div className="config-voice-section-head">
            <span>01</span>
            <div><h4 id="voice-provider-title">Voice source</h4><p>Where speech is recognized and played.</p></div>
          </div>
          <div className="config-voice-provider-options" role="group" aria-label="Voice source">
            {[
              { value: "auto", label: "Automatic", description: "Use OpenAI when ready, otherwise browser speech." },
              { value: "openai", label: "OpenAI", description: "Use OpenAI audio models." },
              { value: "local", label: "Browser", description: "Keep voice processing in this browser." }
            ].map((option) => (
              <button key={option.value} type="button" aria-pressed={provider === option.value}
                className={`config-voice-provider-option ${provider === option.value ? "active" : ""}`}
                onClick={() => update({ provider: option.value })}>
                <strong>{option.label}</strong><small>{option.description}</small>
              </button>
            ))}
          </div>
        </section>

        <section className="config-voice-section" aria-labelledby="voice-input-title">
          <div className="config-voice-section-head">
            <span>02</span>
            <div><h4 id="voice-input-title">Input</h4><p>How spoken messages reach the agent.</p></div>
          </div>
          <div className="config-voice-main-controls">
            <ChoiceGroup
              label="Send message"
              value={input.mode || "push_to_talk"}
              options={[
                { value: "push_to_talk", label: "Push to talk" },
                { value: "auto_submit", label: "Auto submit" }
              ]}
              onChange={(value) => updateInput({ mode: value })}
            />
            <ToggleField
              id="voice-preview-before-send"
              title="Preview before send"
              description="Review the transcript first."
              checked={input.previewBeforeSend !== false}
              onChange={(checked) => updateInput({ previewBeforeSend: checked })}
            />
          </div>
          <details className="config-voice-disclosure">
            <summary><span>Recognition language</span><small>{input.language || "auto"}</small><span className="material-symbols-rounded" aria-hidden="true">expand_more</span></summary>
            <div className="config-voice-disclosure-body">
              <TextField
                id="voice-mode-language"
                label="Language"
                value={input.language || "auto"}
                hint="Use auto or a language code such as en-US or ru-RU."
                onChange={(value) => updateInput({ language: value })}
              />
            </div>
          </details>
        </section>

        <section className="config-voice-section" aria-labelledby="voice-output-title">
          <div className="config-voice-section-head">
            <span>03</span>
            <div><h4 id="voice-output-title">Audio</h4><p>Configure only the sources selected above.</p></div>
          </div>
          <div className="config-voice-sources">
            {provider !== "local" ? <div className="config-voice-source">
              <ToggleField
                id="voice-openai-enabled"
                title="OpenAI audio"
                description="Transcription and generated voice."
                checked={Boolean(openAI.enabled)}
                onChange={(checked) => updateOpenAI({ enabled: checked })}
              />
              {openAI.enabled ? <details className="config-voice-disclosure config-voice-source-details">
                <summary><span>Models &amp; voice</span><small>{ttsModel} · {voice}</small><span className="material-symbols-rounded" aria-hidden="true">expand_more</span></summary>
                <div className="config-voice-disclosure-body config-voice-form">
                  <TextField id="voice-transcription-model" label="Transcription model" value={openAI.transcriptionModel || ""}
                    onChange={(value) => updateOpenAI({ transcriptionModel: value })} />
                  <CapabilityChoiceList label="Transcription models" value={openAI.transcriptionModel || "gpt-4o-mini-transcribe"}
                    options={transcriptionModels} onSelect={(value) => updateOpenAI({ transcriptionModel: value })} />
                  <TextField id="voice-tts-model" label="Speech model" value={openAI.ttsModel || ""}
                    onChange={(value) => updateOpenAI({ ttsModel: value })} />
                  <CapabilityChoiceList label="Speech models" value={ttsModel} options={speechModels}
                    onSelect={(value) => updateOpenAI({ ttsModel: value })} />
                  <TextField id="voice-openai-voice" label="Voice" value={voice}
                    onChange={(value) => updateOpenAI({ voice: value })} />
                  <CapabilityChoiceList label={ttsModel === "gpt-4o-mini-tts" ? "Voices" : "Compatible voices"}
                    value={voice} options={displayedVoiceOptions} onSelect={(value) => updateOpenAI({ voice: value })}
                    getTitle={(option) => option.recommended ? `${option.title || option.id} · recommended` : option.title || option.id} />
                  <label className="config-voice-field config-voice-field-wide" htmlFor="voice-openai-instructions">
                    <span>Voice instructions</span>
                    <textarea id="voice-openai-instructions" value={openAI.instructions || ""}
                      onChange={(event) => updateOpenAI({ instructions: event.target.value })} />
                    <small>Tone and speaking style for generated audio.</small>
                  </label>
                </div>
              </details> : null}
              {openAI.enabled && capabilityStatus ? <p className="config-voice-capability-status">{capabilityStatus}</p> : null}
            </div> : null}

            {provider !== "openai" ? <div className="config-voice-source">
              <ToggleField
                id="voice-local-enabled"
                title="Browser speech"
                description={provider === "auto" ? "Fallback when OpenAI is unavailable." : "Use this browser's speech services."}
                checked={local.enabled !== false}
                onChange={(checked) => updateLocal({ enabled: checked })}
              />
              {local.enabled !== false ? <details className="config-voice-disclosure config-voice-source-details">
                <summary><span>Browser voice</span><small>{local.voiceName || "Browser default"} · {Number(local.rate ?? 1).toFixed(1)}×</small><span className="material-symbols-rounded" aria-hidden="true">expand_more</span></summary>
                <div className="config-voice-disclosure-body config-voice-form">
                  <TextField id="voice-local-name" label="Voice name" value={local.voiceName || ""}
                    hint="Leave empty for the browser default." wide onChange={(value) => updateLocal({ voiceName: value })} />
                  <SliderField id="voice-local-rate" label="Rate" min="0.5" max="2" step="0.1"
                    value={local.rate ?? 1} onChange={(value) => updateLocal({ rate: value })} />
                  <SliderField id="voice-local-pitch" label="Pitch" min="0" max="2" step="0.1"
                    value={local.pitch ?? 1} onChange={(value) => updateLocal({ pitch: value })} />
                </div>
              </details> : null}
            </div> : null}
          </div>
          {provider === "openai" && !openAI.enabled ? <p className="config-voice-warning">Enable OpenAI audio to use this source.</p> : null}
          {provider === "local" && local.enabled === false ? <p className="config-voice-warning">Enable browser speech to use this source.</p> : null}
          {provider === "auto" && !openAI.enabled && local.enabled === false ? <p className="config-voice-warning">Enable at least one audio source.</p> : null}
        </section>
      </>}
    </div>
  );
}
