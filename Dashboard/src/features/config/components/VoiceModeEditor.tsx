import React from "react";

const OPENAI_VOICES = ["alloy", "ash", "ballad", "coral", "echo", "fable", "marin", "nova", "onyx", "sage", "shimmer", "verse"];

export function VoiceModeEditor({ voiceMode, onUpdate }) {
  const provider = voiceMode?.provider || "auto";
  const input = voiceMode?.input || {};
  const openAI = voiceMode?.openAI || {};
  const local = voiceMode?.local || {};

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
    <div className="entry-editor-layout config-voice-layout">
      <section className="entry-editor-card config-voice-card">
        <div className="entry-editor-head">
          <div>
            <span className="entry-editor-kicker">Voice Mode</span>
            <h3>Voice conversation</h3>
          </div>
          <label className="config-field-toggle">
            <input
              type="checkbox"
              checked={Boolean(voiceMode?.enabled)}
              onChange={(event) => update({ enabled: event.target.checked })}
            />
            <span>Enabled</span>
          </label>
        </div>

        <section className="entry-editor-block">
          <h4>Provider</h4>
          <div className="provider-auth-mode-segmented config-segmented" role="tablist" aria-label="Voice provider">
            {[
              ["auto", "Auto"],
              ["openai", "OpenAI"],
              ["local", "Local"]
            ].map(([value, label]) => (
              <button
                key={value}
                type="button"
                className={provider === value ? "active" : ""}
                onClick={() => update({ provider: value })}
              >
                {label}
              </button>
            ))}
          </div>
          <span className="entry-form-hint">
            Auto uses OpenAI when voice credentials are configured, otherwise local browser speech.
          </span>
        </section>

        <section className="entry-editor-block config-voice-grid">
          <label>
            Input mode
            <div className="provider-auth-mode-segmented config-segmented" role="tablist" aria-label="Voice input mode">
              <button
                type="button"
                className={(input.mode || "push_to_talk") === "push_to_talk" ? "active" : ""}
                onClick={() => updateInput({ mode: "push_to_talk" })}
              >
                Push to talk
              </button>
              <button
                type="button"
                className={input.mode === "auto_submit" ? "active" : ""}
                onClick={() => updateInput({ mode: "auto_submit" })}
              >
                Auto submit
              </button>
            </div>
          </label>
          <label>
            Language
            <input value={input.language || "auto"} onChange={(event) => updateInput({ language: event.target.value })} />
          </label>
          <label className="config-field-toggle">
            <input
              type="checkbox"
              checked={input.previewBeforeSend !== false}
              onChange={(event) => updateInput({ previewBeforeSend: event.target.checked })}
            />
            <span>Preview before send</span>
          </label>
        </section>
      </section>

      <section className="entry-editor-card config-voice-card">
        <div className="entry-editor-head">
          <div>
            <span className="entry-editor-kicker">OpenAI</span>
            <h3>Server audio</h3>
          </div>
          <label className="config-field-toggle">
            <input
              type="checkbox"
              checked={Boolean(openAI.enabled)}
              onChange={(event) => updateOpenAI({ enabled: event.target.checked })}
            />
            <span>Use when available</span>
          </label>
        </div>
        <div className="entry-form-grid">
          <label>
            Transcription model
            <input value={openAI.transcriptionModel || ""} onChange={(event) => updateOpenAI({ transcriptionModel: event.target.value })} />
          </label>
          <label>
            TTS model
            <input value={openAI.ttsModel || ""} onChange={(event) => updateOpenAI({ ttsModel: event.target.value })} />
          </label>
          <label>
            Voice
            <input value={openAI.voice || "coral"} onChange={(event) => updateOpenAI({ voice: event.target.value })} />
          </label>
          <div className="entry-form-wide config-voice-picker">
            <span className="entry-form-hint">Quick voice picker</span>
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
          <label className="entry-form-wide">
            Instructions
            <textarea value={openAI.instructions || ""} onChange={(event) => updateOpenAI({ instructions: event.target.value })} />
          </label>
        </div>
      </section>

      <section className="entry-editor-card config-voice-card">
        <div className="entry-editor-head">
          <div>
            <span className="entry-editor-kicker">Local</span>
            <h3>Browser fallback</h3>
          </div>
          <label className="config-field-toggle">
            <input
              type="checkbox"
              checked={local.enabled !== false}
              onChange={(event) => updateLocal({ enabled: event.target.checked })}
            />
            <span>Enabled</span>
          </label>
        </div>
        <div className="entry-form-grid">
          <label>
            Voice name
            <input value={local.voiceName || ""} onChange={(event) => updateLocal({ voiceName: event.target.value })} />
          </label>
          <label>
            Rate
            <input type="number" min="0.5" max="2" step="0.1" value={local.rate ?? 1} onChange={(event) => updateLocal({ rate: Number(event.target.value) })} />
          </label>
          <label>
            Pitch
            <input type="number" min="0" max="2" step="0.1" value={local.pitch ?? 1} onChange={(event) => updateLocal({ pitch: Number(event.target.value) })} />
          </label>
        </div>
      </section>
    </div>
  );
}
