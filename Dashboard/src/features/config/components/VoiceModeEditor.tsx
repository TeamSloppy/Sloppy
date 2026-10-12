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

function TextField({ id, label, value, onChange, hint = "", wide = false, type = "text" }) {
  return (
    <label className={`config-voice-field ${wide ? "config-voice-field-wide" : ""}`} htmlFor={id}>
      <span>{label}</span>
      <input id={id} type={type} value={value} onChange={(event) => onChange(event.target.value)} />
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

function formatSize(bytes) {
  const megabytes = Number(bytes) / (1024 * 1024);
  return megabytes >= 1000 ? `${(megabytes / 1024).toFixed(1)} GB` : `${Math.round(megabytes)} MB`;
}

const WHISPER_STEP_LABELS = {
  whisper_cpp: "Installing whisper.cpp with Homebrew...",
  ffmpeg: "Installing ffmpeg with Homebrew...",
  model: "Downloading the speech model..."
};

function StatusRow({ ok, label, detail = "" }) {
  return (
    <li className={`config-voice-status-row ${ok ? "ok" : ""}`}>
      <span className="material-symbols-rounded" aria-hidden="true">{ok ? "check_circle" : "radio_button_unchecked"}</span>
      <span>{label}</span>
      {detail ? <small>{detail}</small> : null}
    </li>
  );
}

function WhisperSetup({ whisper, onUpdate, fetchWhisperStatus, startWhisperInstall }) {
  const [status, setStatus] = React.useState(null);
  const [selectedModel, setSelectedModel] = React.useState("");
  const [message, setMessage] = React.useState("");
  const job = status?.job || { state: "idle" };
  const isRunning = job.state === "running";

  const refresh = React.useCallback(async () => {
    if (!fetchWhisperStatus) {
      return null;
    }
    const next = await fetchWhisperStatus();
    if (next) {
      setStatus(next);
    }
    return next;
  }, [fetchWhisperStatus]);

  React.useEffect(() => {
    void refresh();
  }, [refresh]);

  React.useEffect(() => {
    if (!isRunning) {
      return undefined;
    }
    const timer = window.setInterval(() => void refresh(), 1000);
    return () => window.clearInterval(timer);
  }, [isRunning, refresh]);

  React.useEffect(() => {
    if (!status || selectedModel) {
      return;
    }
    const recommended = status.models.find((model) => model.recommended) || status.models[0];
    setSelectedModel((status.models.find((model) => model.installed) || recommended)?.id || "");
  }, [status, selectedModel]);

  // When an install finishes, point the config at the new model so the toggle is all that is left.
  React.useEffect(() => {
    if (job.state === "succeeded" && job.modelPath && whisper.modelPath !== job.modelPath) {
      onUpdate({ modelPath: job.modelPath });
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [job.state, job.modelPath]);

  if (!fetchWhisperStatus || !status) {
    return null;
  }

  const model = status.models.find((item) => item.id === selectedModel);
  const toolsReady = Boolean(status.whisperCliPath && status.ffmpegPath);
  const ready = toolsReady && status.models.some((item) => item.installed);
  const needsInstall = !toolsReady || !model?.installed;

  async function install() {
    setMessage("");
    const started = await startWhisperInstall(selectedModel);
    if (!started) {
      setMessage("Could not start the installation. It may already be running.");
    }
    await refresh();
  }

  return (
    <div className="config-voice-setup">
      <ul className="config-voice-status-list" aria-label="On-device recognition status">
        <StatusRow ok={Boolean(status.whisperCliPath)} label="whisper.cpp" detail={status.whisperCliPath || "Not installed"} />
        <StatusRow ok={Boolean(status.ffmpegPath)} label="ffmpeg" detail={status.ffmpegPath || "Not installed"} />
        <StatusRow ok={status.models.some((item) => item.installed)} label="Speech model"
          detail={status.models.find((item) => item.installed)?.fileName || "Not downloaded"} />
      </ul>

      <ChoiceGroup
        label="Model"
        value={selectedModel}
        options={status.models.map((item) => ({
          value: item.id,
          label: `${item.title.split(" (")[0]} · ${formatSize(item.sizeBytes)}${item.installed ? " ✓" : ""}`
        }))}
        onChange={(value) => {
          setSelectedModel(value);
          const chosen = status.models.find((item) => item.id === value);
          if (chosen?.installed && chosen.path) {
            onUpdate({ modelPath: chosen.path });
          }
        }}
      />

      {isRunning ? (
        <div className="config-voice-progress" role="status">
          <span>{WHISPER_STEP_LABELS[job.step] || "Starting..."}</span>
          <progress max="1" value={job.progress ?? undefined} />
        </div>
      ) : (
        <div className="config-voice-setup-actions">
          {status.installable && needsInstall ? (
            <button type="button" className="hover-levitate" onClick={install}>
              {toolsReady ? "Download model" : "Install"} {model ? `(${formatSize(model.sizeBytes)})` : ""}
            </button>
          ) : null}
          {ready && !needsInstall ? <small>Ready. Turn on On-device recognition above to use it.</small> : null}
        </div>
      )}

      {job.state === "failed" ? <p className="config-voice-warning">{job.message || "Installation failed."}</p> : null}
      {job.state === "succeeded" && !isRunning ? <p className="config-voice-capability-status">Installed. Save settings to keep the model path.</p> : null}
      {message ? <p className="config-voice-warning">{message}</p> : null}

      {!status.installable || job.state === "failed" ? (
        <details className="config-voice-disclosure">
          <summary><span>Install manually</span><span className="material-symbols-rounded" aria-hidden="true">expand_more</span></summary>
          <div className="config-voice-disclosure-body">
            {status.manualCommands.map((command) => <pre key={command}><code>{command}</code></pre>)}
          </div>
        </details>
      ) : null}
    </div>
  );
}

export function VoiceModeEditor({ voiceMode, onUpdate, fetchVoiceCapabilities = null, fetchWhisperStatus = null, startWhisperInstall = null }) {
  const [capabilities, setCapabilities] = React.useState(null);
  const [capabilityStatus, setCapabilityStatus] = React.useState(fetchVoiceCapabilities ? "Loading voice options..." : "");
  const provider = voiceMode?.provider || "auto";
  const input = voiceMode?.input || {};
  const openAI = voiceMode?.openAI || {};
  const groq = voiceMode?.groq || {};
  const elevenLabs = voiceMode?.elevenLabs || {};
  const system = voiceMode?.system || {};
  const realtime = voiceMode?.realtime || {};
  const whisper = voiceMode?.whisper || {};
  const transcriptionProvider = voiceMode?.transcriptionProvider || "auto";
  const speechProvider = voiceMode?.speechProvider || "auto";
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

  function updateGroq(patch) {
    update({ groq: { ...groq, ...patch } });
  }

  function updateElevenLabs(patch) {
    update({ elevenLabs: { ...elevenLabs, ...patch } });
  }

  function updateWhisper(patch) {
    update({ whisper: { ...whisper, ...patch } });
  }

  function updateRealtime(patch) {
    update({ realtime: { ...realtime, ...patch } });
  }

  function updateSystem(patch) {
    update({ system: { ...system, ...patch } });
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
          {provider !== "local" ? <div className="config-voice-main-controls">
            <ChoiceGroup
              label="Speech recognition"
              value={transcriptionProvider}
              options={[
                { value: "auto", label: "Automatic" },
                { value: "openai", label: "OpenAI" },
                { value: "groq", label: "Groq" },
                { value: "whisper", label: "On-device" }
              ]}
              onChange={(value) => update({ transcriptionProvider: value })}
            />
            <ChoiceGroup
              label="Speech playback"
              value={speechProvider}
              options={[
                { value: "auto", label: "Automatic" },
                { value: "openai", label: "OpenAI" },
                { value: "elevenlabs", label: "ElevenLabs" },
                { value: "system", label: "System" }
              ]}
              onChange={(value) => update({ speechProvider: value })}
            />
          </div> : null}
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

            {provider !== "local" ? <div className="config-voice-source">
              <ToggleField
                id="voice-groq-enabled"
                title="Groq transcription"
                description="Fast Whisper recognition with a free tier."
                checked={Boolean(groq.enabled)}
                onChange={(checked) => updateGroq({ enabled: checked })}
              />
              {groq.enabled ? <details className="config-voice-disclosure config-voice-source-details">
                <summary><span>Model &amp; key</span><small>{groq.transcriptionModel || "whisper-large-v3-turbo"}</small><span className="material-symbols-rounded" aria-hidden="true">expand_more</span></summary>
                <div className="config-voice-disclosure-body config-voice-form">
                  <TextField id="voice-groq-model" label="Transcription model" value={groq.transcriptionModel || ""}
                    onChange={(value) => updateGroq({ transcriptionModel: value })} />
                  <TextField id="voice-groq-key" label="API key" type="password" value={groq.apiKey || ""}
                    hint="Leave empty to use GROQ_API_KEY from the Core environment." wide
                    onChange={(value) => updateGroq({ apiKey: value })} />
                </div>
              </details> : null}
            </div> : null}

            {provider !== "local" ? <div className="config-voice-source">
              <ToggleField
                id="voice-elevenlabs-enabled"
                title="ElevenLabs voice"
                description="High-quality generated voice with a free tier."
                checked={Boolean(elevenLabs.enabled)}
                onChange={(checked) => updateElevenLabs({ enabled: checked })}
              />
              {elevenLabs.enabled ? <details className="config-voice-disclosure config-voice-source-details">
                <summary><span>Model, voice &amp; key</span><small>{elevenLabs.model || "eleven_multilingual_v2"}</small><span className="material-symbols-rounded" aria-hidden="true">expand_more</span></summary>
                <div className="config-voice-disclosure-body config-voice-form">
                  <TextField id="voice-elevenlabs-model" label="Model" value={elevenLabs.model || ""}
                    onChange={(value) => updateElevenLabs({ model: value })} />
                  <TextField id="voice-elevenlabs-voice" label="Voice ID" value={elevenLabs.voiceId || ""}
                    onChange={(value) => updateElevenLabs({ voiceId: value })} />
                  <TextField id="voice-elevenlabs-key" label="API key" type="password" value={elevenLabs.apiKey || ""}
                    hint="Leave empty to use ELEVENLABS_API_KEY from the Core environment." wide
                    onChange={(value) => updateElevenLabs({ apiKey: value })} />
                </div>
              </details> : null}
            </div> : null}

            {provider !== "local" ? <div className="config-voice-source">
              <ToggleField
                id="voice-system-enabled"
                title="System voice"
                description="Offline speech from the machine running Core (macOS)."
                checked={Boolean(system.enabled)}
                onChange={(checked) => updateSystem({ enabled: checked })}
              />
              {system.enabled ? <details className="config-voice-disclosure config-voice-source-details">
                <summary><span>Voice</span><small>{system.voice || "System default"}</small><span className="material-symbols-rounded" aria-hidden="true">expand_more</span></summary>
                <div className="config-voice-disclosure-body config-voice-form">
                  <TextField id="voice-system-name" label="Voice name" value={system.voice || ""}
                    hint="For example Milena for Russian. Leave empty for the system default." wide
                    onChange={(value) => updateSystem({ voice: value })} />
                </div>
              </details> : null}
            </div> : null}

            <div className="config-voice-source">
              <ToggleField
                id="voice-whisper-enabled"
                title="On-device recognition (whisper.cpp)"
                description="Offline speech recognition on the machine running Core. Audio never leaves it."
                checked={Boolean(whisper.enabled)}
                onChange={(checked) => updateWhisper({ enabled: checked })}
              />
              {whisper.enabled ? <>
                <WhisperSetup whisper={whisper} onUpdate={updateWhisper}
                  fetchWhisperStatus={fetchWhisperStatus} startWhisperInstall={startWhisperInstall} />
                <details className="config-voice-disclosure config-voice-source-details">
                  <summary><span>Advanced</span><small>{whisper.modelPath ? whisper.modelPath.split("/").pop() : "Automatic model"}</small><span className="material-symbols-rounded" aria-hidden="true">expand_more</span></summary>
                  <div className="config-voice-disclosure-body config-voice-form">
                    <TextField id="voice-whisper-model" label="Model file" value={whisper.modelPath || ""} wide
                      hint="Leave empty to use the model installed above, or point to any ggml model file."
                      onChange={(value) => updateWhisper({ modelPath: value })} />
                    <TextField id="voice-whisper-exe" label="whisper-cli path" value={whisper.executablePath || ""}
                      hint="Leave empty to find whisper-cli automatically."
                      onChange={(value) => updateWhisper({ executablePath: value })} />
                    <TextField id="voice-whisper-ffmpeg" label="ffmpeg path" value={whisper.ffmpegPath || ""}
                      hint="Leave empty to find ffmpeg automatically."
                      onChange={(value) => updateWhisper({ ffmpegPath: value })} />
                  </div>
                </details>
              </> : null}
            </div>

            <div className="config-voice-source">
              <ToggleField
                id="voice-realtime-enabled"
                title="Live conversation (Gemini)"
                description="Natural two-way voice with interruptions. Uses Gemini Live; the browser connects directly with a short-lived token."
                checked={Boolean(realtime.enabled)}
                onChange={(checked) => updateRealtime({ enabled: checked })}
              />
              {realtime.enabled ? <details className="config-voice-disclosure config-voice-source-details">
                <summary><span>Model, voice &amp; key</span><small>{realtime.model || "gemini-3.8-live"} · {realtime.voice || "Puck"}</small><span className="material-symbols-rounded" aria-hidden="true">expand_more</span></summary>
                <div className="config-voice-disclosure-body config-voice-form">
                  <TextField id="voice-realtime-model" label="Live model" value={realtime.model || ""}
                    hint="Use the Live model name from the Gemini API docs." onChange={(value) => updateRealtime({ model: value })} />
                  <TextField id="voice-realtime-voice" label="Voice" value={realtime.voice || ""}
                    onChange={(value) => updateRealtime({ voice: value })} />
                  <TextField id="voice-realtime-key" label="API key" type="password" value={realtime.apiKey || ""}
                    hint="Leave empty to use GEMINI_API_KEY from the Core environment or a configured Gemini model." wide
                    onChange={(value) => updateRealtime({ apiKey: value })} />
                  <label className="config-voice-field config-voice-field-wide" htmlFor="voice-realtime-instruction">
                    <span>System instruction</span>
                    <textarea id="voice-realtime-instruction" value={realtime.systemInstruction || ""}
                      onChange={(event) => updateRealtime({ systemInstruction: event.target.value })} />
                    <small>Live sessions talk to Gemini directly, not to your agent or its tools.</small>
                  </label>
                </div>
              </details> : null}
            </div>

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
          {transcriptionProvider === "whisper" && !whisper.enabled && provider !== "local" ? <p className="config-voice-warning">Enable on-device recognition to use it.</p> : null}
          {transcriptionProvider === "groq" && !groq.enabled && provider !== "local" ? <p className="config-voice-warning">Enable Groq transcription to use it for recognition.</p> : null}
          {provider === "local" && local.enabled === false ? <p className="config-voice-warning">Enable browser speech to use this source.</p> : null}
          {provider === "auto" && !openAI.enabled && local.enabled === false ? <p className="config-voice-warning">Enable at least one audio source.</p> : null}
        </section>
      </>}
    </div>
  );
}
