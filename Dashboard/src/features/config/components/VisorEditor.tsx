import React from "react";

function buildModelOptions(models) {
  const options = [{ value: "", label: "Default system model" }];
  for (const entry of Array.isArray(models) ? models : []) {
    const title = String(entry?.title || "").trim();
    const model = String(entry?.model || "").trim();
    if (!model) continue;
    const label = title ? `${title} — ${model}` : model;
    options.push({ value: model, label });
  }
  return options;
}

export function VisorEditor({ draftConfig, mutateDraft, parseLines }) {
  const visor = draftConfig.visor || {};
  const scheduler = visor.scheduler || {};
  const schedulerEnabled = Boolean(scheduler.enabled !== false);
  const intervalSeconds = scheduler.intervalSeconds ?? 300;
  const jitterSeconds = scheduler.jitterSeconds ?? 60;
  const bootstrapBulletin = Boolean(visor.bootstrapBulletin !== false);
  const bulletinMaxWords = visor.bulletinMaxWords ?? 300;
  const model = String(visor.model || "");
  const tickIntervalSeconds = visor.tickIntervalSeconds ?? 30;
  const workerTimeoutSeconds = visor.workerTimeoutSeconds ?? 600;
  const branchTimeoutSeconds = visor.branchTimeoutSeconds ?? 60;
  const maintenanceIntervalSeconds = visor.maintenanceIntervalSeconds ?? 3600;
  const decayRatePerDay = visor.decayRatePerDay ?? 0.05;
  const pruneImportanceThreshold = visor.pruneImportanceThreshold ?? 0.1;
  const pruneMinAgeDays = visor.pruneMinAgeDays ?? 30;
  const channelDegradedFailureCount = visor.channelDegradedFailureCount ?? 3;
  const channelDegradedWindowSeconds = visor.channelDegradedWindowSeconds ?? 600;
  const idleThresholdSeconds = visor.idleThresholdSeconds ?? 1800;
  const webhookURLs = Array.isArray(visor.webhookURLs) ? visor.webhookURLs : [];
  const mergeEnabled = Boolean(visor.mergeEnabled);
  const mergeSimilarityThreshold = visor.mergeSimilarityThreshold ?? 0.80;
  const mergeMaxPerRun = visor.mergeMaxPerRun ?? 10;

  function setVisor(field, value) {
    mutateDraft((draft) => {
      if (!draft.visor) draft.visor = {};
      draft.visor[field] = value;
    });
  }

  function setScheduler(field, value) {
    mutateDraft((draft) => {
      if (!draft.visor) draft.visor = {};
      if (!draft.visor.scheduler) draft.visor.scheduler = {};
      draft.visor.scheduler[field] = value;
    });
  }

  function parseIntField(raw, fallback) {
    const parsed = parseInt(raw, 10);
    return Number.isFinite(parsed) ? parsed : fallback;
  }

  function parseFloatField(raw, fallback) {
    const parsed = parseFloat(raw);
    return Number.isFinite(parsed) ? parsed : fallback;
  }

  return (
    <div className="tg-settings-shell">
      <section className="entry-editor-card providers-intro-card">
        <h3>Visor</h3>
        <p className="placeholder-text">
          Visor is the runtime supervision layer. It monitors worker and branch health, maintains memory over time, and generates periodic bulletins that keep agents aware of what's happening in the system.
        </p>
      </section>

      <section className="entry-editor-card">
        <h3>Bulletin Scheduler</h3>
        <div className="entry-form-grid">
          <label style={{ gridColumn: "1 / -1" }}>
            Scheduler
            <select
              value={schedulerEnabled ? "enabled" : "disabled"}
              onChange={(event) => setScheduler("enabled", event.target.value === "enabled")}
            >
              <option value="enabled">Enabled</option>
              <option value="disabled">Disabled</option>
            </select>
            <span className="entry-form-hint">When enabled, Visor generates a bulletin on a regular schedule. Disable if you prefer on-demand bulletin generation only.</span>
          </label>

          <label>
            Interval (seconds)
            <input
              type="number"
              min={30}
              disabled={!schedulerEnabled}
              value={intervalSeconds}
              onChange={(event) => setScheduler("intervalSeconds", parseIntField(event.target.value, 300))}
            />
            <span className="entry-form-hint">How often to generate a bulletin. Default: 300 s (5 min).</span>
          </label>

          <label>
            Jitter (seconds)
            <input
              type="number"
              min={0}
              disabled={!schedulerEnabled}
              value={jitterSeconds}
              onChange={(event) => setScheduler("jitterSeconds", parseIntField(event.target.value, 60))}
            />
            <span className="entry-form-hint">Random delay added to each interval to avoid bursts. Default: 60 s.</span>
          </label>

          <label style={{ gridColumn: "1 / -1" }}>
            Bootstrap Bulletin
            <select
              value={bootstrapBulletin ? "enabled" : "disabled"}
              onChange={(event) => setVisor("bootstrapBulletin", event.target.value === "enabled")}
            >
              <option value="enabled">Generate on startup</option>
              <option value="disabled">Skip on startup</option>
            </select>
            <span className="entry-form-hint">When enabled, a bulletin is generated immediately when Sloppy starts so agents have context from the first message.</span>
          </label>
        </div>
      </section>

      <section className="entry-editor-card">
        <h3>Bulletin Content</h3>
        <div className="entry-form-grid">
          <label style={{ gridColumn: "1 / -1" }}>
            Model
            <select
              value={model}
              onChange={(event) => setVisor("model", event.target.value || null)}
            >
              {buildModelOptions(draftConfig.models).map((option) => (
                <option key={option.value} value={option.value}>{option.label}</option>
              ))}
            </select>
            <span className="entry-form-hint">Model used to synthesize bulletin text. When set to default, the first configured system model is used.</span>
          </label>

          <label>
            Max Words
            <input
              type="number"
              min={50}
              max={1000}
              value={bulletinMaxWords}
              onChange={(event) => setVisor("bulletinMaxWords", parseIntField(event.target.value, 300))}
            />
            <span className="entry-form-hint">Target word count for the bulletin digest. Default: 300.</span>
          </label>
        </div>
      </section>

      <section className="entry-editor-card">
        <h3>Supervision</h3>
        <div className="entry-form-grid">
          <label>
            Tick Interval (seconds)
            <input
              type="number"
              min={5}
              value={tickIntervalSeconds}
              onChange={(event) => setVisor("tickIntervalSeconds", parseIntField(event.target.value, 30))}
            />
            <span className="entry-form-hint">How often the supervision loop runs. Default: 30 s.</span>
          </label>

          <label>
            Worker Timeout (seconds)
            <input
              type="number"
              min={30}
              value={workerTimeoutSeconds}
              onChange={(event) => setVisor("workerTimeoutSeconds", parseIntField(event.target.value, 600))}
            />
            <span className="entry-form-hint">How long a worker may stay running before a timeout event is fired. Default: 600 s (10 min).</span>
          </label>

          <label>
            Branch Timeout (seconds)
            <input
              type="number"
              min={5}
              value={branchTimeoutSeconds}
              onChange={(event) => setVisor("branchTimeoutSeconds", parseIntField(event.target.value, 60))}
            />
            <span className="entry-form-hint">How long a branch may stay active before Visor force-concludes it. Default: 60 s.</span>
          </label>
        </div>
      </section>

      <section className="entry-editor-card">
        <h3>Memory Maintenance</h3>
        <div className="entry-form-grid">
          <label style={{ gridColumn: "1 / -1" }}>
            Maintenance Interval (seconds)
            <input
              type="number"
              min={60}
              value={maintenanceIntervalSeconds}
              onChange={(event) => setVisor("maintenanceIntervalSeconds", parseIntField(event.target.value, 3600))}
            />
            <span className="entry-form-hint">How often decay, pruning, and merge passes run. Default: 3600 s (1 hour).</span>
          </label>

          <label>
            Decay Rate / Day
            <input
              type="number"
              min={0}
              max={1}
              step={0.01}
              value={decayRatePerDay}
              onChange={(event) => setVisor("decayRatePerDay", parseFloatField(event.target.value, 0.05))}
            />
            <span className="entry-form-hint">Fraction of importance lost each day. 0.05 = 5% per day. Set to 0 to disable decay.</span>
          </label>

          <label>
            Prune Threshold
            <input
              type="number"
              min={0}
              max={1}
              step={0.01}
              value={pruneImportanceThreshold}
              onChange={(event) => setVisor("pruneImportanceThreshold", parseFloatField(event.target.value, 0.1))}
            />
            <span className="entry-form-hint">Memories below this importance score become candidates for pruning. Default: 0.1.</span>
          </label>

          <label>
            Prune Min Age (days)
            <input
              type="number"
              min={1}
              value={pruneMinAgeDays}
              onChange={(event) => setVisor("pruneMinAgeDays", parseIntField(event.target.value, 30))}
            />
            <span className="entry-form-hint">A memory must be at least this old before it can be pruned. Default: 30 days.</span>
          </label>
        </div>
      </section>

      <section className="entry-editor-card">
        <h3>Channel Health</h3>
        <div className="entry-form-grid">
          <label>
            Degraded Failure Count
            <input
              type="number"
              min={1}
              value={channelDegradedFailureCount}
              onChange={(event) => setVisor("channelDegradedFailureCount", parseIntField(event.target.value, 3))}
            />
            <span className="entry-form-hint">Number of worker failures in a channel within the window to trigger a degraded signal. Default: 3.</span>
          </label>

          <label>
            Failure Window (seconds)
            <input
              type="number"
              min={60}
              value={channelDegradedWindowSeconds}
              onChange={(event) => setVisor("channelDegradedWindowSeconds", parseIntField(event.target.value, 600))}
            />
            <span className="entry-form-hint">Sliding time window for counting failures. Default: 600 s (10 min).</span>
          </label>

          <label style={{ gridColumn: "1 / -1" }}>
            Idle Threshold (seconds)
            <input
              type="number"
              min={60}
              value={idleThresholdSeconds}
              onChange={(event) => setVisor("idleThresholdSeconds", parseIntField(event.target.value, 1800))}
            />
            <span className="entry-form-hint">Inactivity period before an idle signal is emitted. Default: 1800 s (30 min).</span>
          </label>
        </div>
      </section>

      <section className="entry-editor-card">
        <h3>Webhooks</h3>
        <div className="entry-form-grid">
          <label style={{ gridColumn: "1 / -1" }}>
            Webhook URLs
            <textarea
              rows={4}
              placeholder={"https://hooks.example.com/alert\nhttps://hooks.example.com/other"}
              value={webhookURLs.join("\n")}
              onChange={(event) => setVisor("webhookURLs", parseLines(event.target.value))}
            />
            <span className="entry-form-hint">One URL per line. POSTed with the event payload when a <code>visor.signal.*</code> event fires (channel degraded, idle).</span>
          </label>
        </div>
      </section>

      <section className="entry-editor-card">
        <h3>Memory Merge</h3>
        <div className="entry-form-grid">
          <label style={{ gridColumn: "1 / -1" }}>
            Memory Merge
            <select
              value={mergeEnabled ? "enabled" : "disabled"}
              onChange={(event) => setVisor("mergeEnabled", event.target.value === "enabled")}
            >
              <option value="disabled">Disabled</option>
              <option value="enabled">Enabled</option>
            </select>
            <span className="entry-form-hint">When enabled, Visor consolidates similar memory entries into one during each maintenance pass. Requires a good recall backend to work effectively.</span>
          </label>

          <label>
            Similarity Threshold
            <input
              type="number"
              min={0}
              max={1}
              step={0.01}
              disabled={!mergeEnabled}
              value={mergeSimilarityThreshold}
              onChange={(event) => setVisor("mergeSimilarityThreshold", parseFloatField(event.target.value, 0.80))}
            />
            <span className="entry-form-hint">Minimum recall score (0–1) to consider two memories as merge candidates. Default: 0.80.</span>
          </label>

          <label>
            Max Merges / Run
            <input
              type="number"
              min={1}
              max={100}
              disabled={!mergeEnabled}
              value={mergeMaxPerRun}
              onChange={(event) => setVisor("mergeMaxPerRun", parseIntField(event.target.value, 10))}
            />
            <span className="entry-form-hint">Maximum number of merge operations per maintenance pass. Default: 10.</span>
          </label>
        </div>
      </section>
    </div>
  );
}
