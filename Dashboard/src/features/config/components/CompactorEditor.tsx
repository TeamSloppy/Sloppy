import React from "react";

const LEVEL_OPTIONS = ["soft", "aggressive", "emergency"];

type CompactorEditorProps = {
  draftConfig: Record<string, any>;
  mutateDraft: (mutator: (draft: Record<string, any>) => void) => void;
};

function parseIntField(raw: unknown, fallback: number) {
  const parsed = parseInt(String(raw), 10);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function parseFloatField(raw: unknown, fallback: number) {
  const parsed = parseFloat(String(raw));
  return Number.isFinite(parsed) ? parsed : fallback;
}

function clamp(value: number, min: number, max: number) {
  return Math.min(max, Math.max(min, value));
}

function thresholdPercent(level: Record<string, any>) {
  const raw = level?.utilizationThreshold ?? 0.8;
  const ratio = Number(raw) > 1 ? Number(raw) / 100 : Number(raw);
  return Math.round(clamp(Number.isFinite(ratio) ? ratio : 0.8, 0, 1) * 100);
}

function defaultLevel(level: string, utilizationThreshold: number, targetReductionPercent: number) {
  return {
    level,
    utilizationThreshold,
    targetReductionPercent,
    preserveRecentMessages: 8,
    preserveRecentTokens: 2000
  };
}

function defaultCompactor() {
  return {
    enabled: true,
    contextWindowTokens: 32000,
    levels: [
      defaultLevel("soft", 0.8, 30),
      defaultLevel("aggressive", 0.85, 50),
      defaultLevel("emergency", 0.95, 70)
    ],
    retry: {
      maxAttempts: 3,
      initialBackoffMs: 250,
      multiplier: 2.0,
      maxBackoffMs: 2000
    }
  };
}

export function CompactorEditor({ draftConfig, mutateDraft }: CompactorEditorProps) {
  const compactor = {
    ...defaultCompactor(),
    ...(draftConfig.compactor || {}),
    retry: {
      ...defaultCompactor().retry,
      ...(draftConfig.compactor?.retry || {})
    }
  };
  const levels = Array.isArray(compactor.levels) && compactor.levels.length > 0
    ? compactor.levels
    : defaultCompactor().levels;
  const enabled = compactor.enabled !== false;

  function setCompactor(field: string, value: any) {
    mutateDraft((draft) => {
      if (!draft.compactor) draft.compactor = defaultCompactor();
      draft.compactor[field] = value;
    });
  }

  function setRetry(field: string, value: any) {
    mutateDraft((draft) => {
      if (!draft.compactor) draft.compactor = defaultCompactor();
      if (!draft.compactor.retry) draft.compactor.retry = defaultCompactor().retry;
      draft.compactor.retry[field] = value;
    });
  }

  function updateLevel(index: number, patch: Record<string, any>) {
    mutateDraft((draft) => {
      if (!draft.compactor) draft.compactor = defaultCompactor();
      const currentLevels = Array.isArray(draft.compactor.levels) && draft.compactor.levels.length > 0
        ? draft.compactor.levels
        : defaultCompactor().levels;
      draft.compactor.levels = currentLevels.map((item: Record<string, any>, itemIndex: number) => (
        itemIndex === index ? { ...item, ...patch } : item
      ));
    });
  }

  function addLevel() {
    mutateDraft((draft) => {
      if (!draft.compactor) draft.compactor = defaultCompactor();
      const currentLevels = Array.isArray(draft.compactor.levels) ? draft.compactor.levels : [];
      draft.compactor.levels = [
        ...currentLevels,
        defaultLevel("soft", 0.8, 50)
      ];
    });
  }

  function removeLevel(index: number) {
    mutateDraft((draft) => {
      if (!draft.compactor) draft.compactor = defaultCompactor();
      const currentLevels = Array.isArray(draft.compactor.levels) ? draft.compactor.levels : [];
      const nextLevels = currentLevels.filter((_: unknown, itemIndex: number) => itemIndex !== index);
      draft.compactor.levels = nextLevels.length > 0 ? nextLevels : defaultCompactor().levels;
    });
  }

  function resetDefaults() {
    mutateDraft((draft) => {
      draft.compactor = defaultCompactor();
    });
  }

  return (
    <div className="tg-settings-shell compactor-settings-shell">
      <section className="entry-editor-card providers-intro-card">
        <h3>Context Compactor</h3>
        <p className="placeholder-text">
          Configure when Sloppy compacts long channel context and how aggressive each compaction pass should be.
          Thresholds are based on estimated tokens used against the context window below.
        </p>
      </section>

      <section className="entry-editor-card">
        <h3>Runtime Trigger</h3>
        <div className="entry-form-grid">
          <label style={{ gridColumn: "1 / -1" }}>
            Compactor
            <select
              value={enabled ? "enabled" : "disabled"}
              onChange={(event) => setCompactor("enabled", event.target.value === "enabled")}
            >
              <option value="enabled">Enabled</option>
              <option value="disabled">Disabled</option>
            </select>
            <span className="entry-form-hint">
              Disable to stop automatic context compaction after messages. Existing memory and summaries are not deleted.
            </span>
          </label>

          <label style={{ gridColumn: "1 / -1" }}>
            Context Window Tokens
            <input
              type="number"
              min={1000}
              step={1000}
              disabled={!enabled}
              value={compactor.contextWindowTokens ?? 32000}
              onChange={(event) => setCompactor("contextWindowTokens", Math.max(1, parseIntField(event.target.value, 32000)))}
            />
            <span className="entry-form-hint">
              Token budget used to estimate utilization. Example: 64000 means a 70% threshold triggers around 44.8k used tokens.
            </span>
          </label>
        </div>
      </section>

      <section className="entry-editor-card">
        <div className="settings-section-heading-row">
          <div>
            <h3>Compaction Levels</h3>
            <p className="placeholder-text">
              The highest matching threshold wins. Reduction percent and preservation limits are passed into the compaction job.
            </p>
          </div>
          <button type="button" className="secondary-button" onClick={addLevel}>Add level</button>
        </div>

        <div className="entry-list-stack">
          {levels.map((level: Record<string, any>, index: number) => {
            const threshold = thresholdPercent(level);
            return (
              <div className="entry-editor-card compact-entry-card" key={`${level.level || "level"}-${index}`}>
                <div className="entry-form-grid">
                  <label>
                    Level
                    <select
                      disabled={!enabled}
                      value={String(level.level || "soft")}
                      onChange={(event) => updateLevel(index, { level: event.target.value })}
                    >
                      {LEVEL_OPTIONS.map((option) => <option key={option} value={option}>{option}</option>)}
                    </select>
                  </label>

                  <label>
                    Trigger at Used Context (%)
                    <input
                      type="number"
                      min={0}
                      max={100}
                      step={1}
                      disabled={!enabled}
                      value={threshold}
                      onChange={(event) => {
                        const percent = clamp(parseFloatField(event.target.value, threshold), 0, 100);
                        updateLevel(index, { utilizationThreshold: percent / 100 });
                      }}
                    />
                    <span className="entry-form-hint">When estimated context usage crosses this percent.</span>
                  </label>

                  <label>
                    Compact Target (%)
                    <input
                      type="number"
                      min={1}
                      max={100}
                      step={1}
                      disabled={!enabled}
                      value={level.targetReductionPercent ?? 50}
                      onChange={(event) => updateLevel(index, {
                        targetReductionPercent: clamp(parseIntField(event.target.value, 50), 1, 100)
                      })}
                    />
                    <span className="entry-form-hint">Target reduction for this compaction job.</span>
                  </label>

                  <label>
                    Preserve Recent Messages
                    <input
                      type="number"
                      min={0}
                      step={1}
                      disabled={!enabled}
                      value={level.preserveRecentMessages ?? 8}
                      onChange={(event) => updateLevel(index, {
                        preserveRecentMessages: Math.max(0, parseIntField(event.target.value, 8))
                      })}
                    />
                    <span className="entry-form-hint">Recent messages protected from summarization.</span>
                  </label>

                  <label>
                    Preserve Recent Tokens
                    <input
                      type="number"
                      min={0}
                      step={500}
                      disabled={!enabled}
                      value={level.preserveRecentTokens ?? 2000}
                      onChange={(event) => updateLevel(index, {
                        preserveRecentTokens: Math.max(0, parseIntField(event.target.value, 2000))
                      })}
                    />
                    <span className="entry-form-hint">Approximate recent-token budget to keep verbatim.</span>
                  </label>

                  <div className="entry-form-actions" style={{ alignSelf: "end" }}>
                    <button
                      type="button"
                      className="secondary-button danger-button"
                      disabled={levels.length <= 1}
                      onClick={() => removeLevel(index)}
                    >
                      Remove
                    </button>
                  </div>
                </div>
              </div>
            );
          })}
        </div>
      </section>

      <section className="entry-editor-card">
        <h3>Retry Policy</h3>
        <div className="entry-form-grid">
          <label>
            Max Attempts
            <input
              type="number"
              min={1}
              step={1}
              disabled={!enabled}
              value={compactor.retry?.maxAttempts ?? 3}
              onChange={(event) => setRetry("maxAttempts", Math.max(1, parseIntField(event.target.value, 3)))}
            />
            <span className="entry-form-hint">How many times a compaction job may be attempted. Default: 3.</span>
          </label>

          <label>
            Initial Backoff (ms)
            <input
              type="number"
              min={0}
              step={50}
              disabled={!enabled}
              value={compactor.retry?.initialBackoffMs ?? 250}
              onChange={(event) => setRetry("initialBackoffMs", Math.max(0, parseIntField(event.target.value, 250)))}
            />
            <span className="entry-form-hint">Delay before first retry. Default: 250 ms.</span>
          </label>

          <label>
            Backoff Multiplier
            <input
              type="number"
              min={1}
              step={0.1}
              disabled={!enabled}
              value={compactor.retry?.multiplier ?? 2.0}
              onChange={(event) => setRetry("multiplier", Math.max(1, parseFloatField(event.target.value, 2.0)))}
            />
            <span className="entry-form-hint">Multiplier applied after each retry. Default: 2.0.</span>
          </label>

          <label>
            Max Backoff (ms)
            <input
              type="number"
              min={0}
              step={100}
              disabled={!enabled}
              value={compactor.retry?.maxBackoffMs ?? 2000}
              onChange={(event) => setRetry("maxBackoffMs", Math.max(0, parseIntField(event.target.value, 2000)))}
            />
            <span className="entry-form-hint">Upper bound for retry delay. Default: 2000 ms.</span>
          </label>
        </div>
      </section>

      <section className="entry-editor-card">
        <h3>Defaults</h3>
        <p className="placeholder-text">
          Default levels preserve existing behavior: soft at 80% with 30% reduction, aggressive at 85% with 50%, emergency at 95% with 70%.
        </p>
        <button type="button" className="secondary-button" onClick={resetDefaults}>Reset compactor defaults</button>
      </section>
    </div>
  );
}
