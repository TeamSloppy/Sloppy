import React from "react";
import { DiscordEditor } from "./DiscordEditor";
import { TelegramEditor } from "./TelegramEditor";

export function ChannelsEditor({ draftConfig, mutateDraft, parseInteger }) {
  return (
    <div className="tg-settings-shell">
      <section className="entry-editor-card providers-intro-card">
        <h3>Channels</h3>
        <p className="placeholder-text">
          Connect messaging platforms to route incoming messages to agents.
        </p>
      </section>
      <section className="entry-editor-card">
        <h3>Channel Lifetime</h3>
        <div className="entry-form-grid">
          <label style={{ gridColumn: "1 / -1" }}>
            Close inactive channels after (days)
            <input
              type="number"
              min="0"
              step="1"
              value={draftConfig.channels.channelInactivityDays}
              onChange={(event) =>
                mutateDraft((draft) => {
                  draft.channels.channelInactivityDays = parseInteger(event.target.value, 2);
                })
              }
            />
            <span className="entry-form-hint">
              Channels with no activity for this many days will be closed automatically. Set to 0 to disable.
            </span>
          </label>
        </div>
      </section>
      <TelegramEditor draftConfig={draftConfig} mutateDraft={mutateDraft} />
      <DiscordEditor draftConfig={draftConfig} mutateDraft={mutateDraft} />
    </div>
  );
}
