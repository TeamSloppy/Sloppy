import React from "react";

const MEMORY_PROVIDER_MODES = [
  { value: "local", label: "Built-in (Local)", description: "Use Sloppy's built-in local memory provider." },
  { value: "http", label: "Remote HTTP", description: "Call an external HTTP memory provider." },
  { value: "mcp", label: "Remote MCP", description: "Route memory operations through an MCP server." }
];

export function MemoryProviderEditor({ draftConfig, mutateDraft }) {
  const memoryProviderMode = String(draftConfig.memory?.provider?.mode || "local");
  const memoryProviderOption = MEMORY_PROVIDER_MODES.find((option) => option.value === memoryProviderMode) || MEMORY_PROVIDER_MODES[0];
  const [memoryProviderMenuOpen, setMemoryProviderMenuOpen] = React.useState(false);

  function parseInteger(value, fallback) {
    const parsed = Number.parseInt(value, 10);
    return Number.isFinite(parsed) ? parsed : fallback;
  }
  function selectMemoryProviderMode(value) {
    mutateDraft((draft) => {
      draft.memory.provider.mode = value;
      if (value === "local") {
        draft.memory.provider.endpoint = "";
        draft.memory.provider.mcpServer = "";
        draft.memory.provider.apiKeyEnv = "";
      }
    });
    setMemoryProviderMenuOpen(false);
  }
  return <><section className="entry-editor-card">
    <h3>Memory provider</h3>
    <div className="entry-form-grid">
          <label>
            Memory Backend
            <input
              value={draftConfig.memory.backend}
              onChange={(event) =>
                mutateDraft((draft) => {
                  draft.memory.backend = event.target.value;
                })
              }
            />
            <span className="entry-form-hint">Storage backend for memory records and embeddings.</span>
          </label>
          <label>
            Memory Provider Mode
            <div className="actor-team-search-wrap config-memory-mode-picker">
              <input
                className="actor-team-search"
                value={memoryProviderOption.label}
                readOnly
                onFocus={() => setMemoryProviderMenuOpen(true)}
                onClick={() => setMemoryProviderMenuOpen(true)}
                onBlur={() => setTimeout(() => setMemoryProviderMenuOpen(false), 150)}
              />
              {memoryProviderMenuOpen ? (
                <ul className="actor-team-dropdown">
                  {MEMORY_PROVIDER_MODES.map((option) => {
                    const selected = option.value === memoryProviderMode;
                    return (
                      <li
                        key={option.value}
                        className={`actor-team-dropdown-item ${selected ? "selected" : ""}`}
                        onMouseDown={(event) => {
                          event.preventDefault();
                          selectMemoryProviderMode(option.value);
                        }}
                      >
                        <span className="actor-team-dropdown-name">{option.label}</span>
                        <span className="actor-team-dropdown-id">{option.description}</span>
                        {selected ? <span className="actor-team-dropdown-check">✓</span> : null}
                      </li>
                    );
                  })}
                </ul>
              ) : null}
            </div>
            <span className="entry-form-hint">Choose where semantic memory operations are executed.</span>
          </label>
          {memoryProviderMode === "http" ? (
            <>
              <label>
                Memory Remote Endpoint
                <input
                  placeholder="https://memory.example.com"
                  value={draftConfig.memory.provider.endpoint || ""}
                  onChange={(event) =>
                    mutateDraft((draft) => {
                      draft.memory.provider.endpoint = event.target.value;
                    })
                  }
                />
                <span className="entry-form-hint">HTTP endpoint for an external memory provider.</span>
              </label>
              <label>
                Memory API Key Env
                <input
                  placeholder="MEMORY_API_KEY"
                  value={draftConfig.memory.provider.apiKeyEnv || ""}
                  onChange={(event) =>
                    mutateDraft((draft) => {
                      draft.memory.provider.apiKeyEnv = event.target.value;
                    })
                  }
                />
                <span className="entry-form-hint">Environment variable containing the memory provider API key.</span>
              </label>
            </>
          ) : null}
          {memoryProviderMode === "mcp" ? (
            <label>
              Memory MCP Server
              <input
                placeholder="memory-server"
                value={draftConfig.memory.provider.mcpServer || ""}
                onChange={(event) =>
                  mutateDraft((draft) => {
                    draft.memory.provider.mcpServer = event.target.value;
                  })
                }
              />
              <span className="entry-form-hint">Configured MCP server ID that handles memory operations.</span>
            </label>
          ) : null}
          <label>
            Memory Timeout (ms)
            <input
              value={String(draftConfig.memory.provider.timeoutMs ?? 2500)}
              onChange={(event) =>
                mutateDraft((draft) => {
                  draft.memory.provider.timeoutMs = parseInteger(event.target.value, 2500);
                })
              }
            />
            <span className="entry-form-hint">Maximum time to wait for memory provider calls.</span>
          </label>
    </div>
  </section>
    {[
      { key: "retrieval", title: "Retrieval", fields: [
        { key: "topK", label: "Default recall limit", min: 1, step: 1 },
        { key: "semanticWeight", label: "Semantic weight", min: 0, step: 0.05 },
        { key: "keywordWeight", label: "Keyword weight", min: 0, step: 0.05 },
        { key: "graphWeight", label: "Graph weight", min: 0, step: 0.05 }
      ] },
      { key: "retention", title: "Retention", fields: [
        { key: "episodicDays", label: "Episodic memory (days)", min: 1, step: 1 },
        { key: "todoCompletedDays", label: "Completed tasks (days)", min: 1, step: 1 },
        { key: "bulletinDays", label: "Bulletins (days)", min: 1, step: 1 }
      ] }
    ].map((group) => <section key={group.key} className="entry-editor-card">
      <h3>{group.title}</h3><div className="entry-form-grid">{group.fields.map((field) => <label key={field.key}>{field.label}
        <input type="number" min={field.min} step={field.step} value={draftConfig.memory[group.key][field.key]}
          onChange={(event) => {
            const value = event.target.valueAsNumber;
            if (Number.isFinite(value)) mutateDraft((draft) => { draft.memory[group.key][field.key] = Math.max(field.min, value); });
          }} />
      </label>)}</div>
    </section>)}
  </>;
}
