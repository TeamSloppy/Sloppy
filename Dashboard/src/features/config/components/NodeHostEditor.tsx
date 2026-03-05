import React from "react";

export function NodeHostEditor({ draftConfig, mutateDraft, parseLines }) {
  const memoryProviderMode = String(draftConfig.memory?.provider?.mode || "local");

  function parseInteger(value, fallback) {
    const parsed = Number.parseInt(value, 10);
    return Number.isFinite(parsed) ? parsed : fallback;
  }

  return (
    <section className="entry-editor-card">
      <h3>NodeHost & Runtime</h3>
      <div className="entry-form-grid">
        <label>
          Listen Host
          <input
            value={draftConfig.listen.host}
            onChange={(event) =>
              mutateDraft((draft) => {
                draft.listen.host = event.target.value;
              })
            }
          />
        </label>
        <label>
          Listen Port
          <input
            value={String(draftConfig.listen.port)}
            onChange={(event) =>
              mutateDraft((draft) => {
                draft.listen.port = Number.parseInt(event.target.value, 10) || 25101;
              })
            }
          />
        </label>
        <label>
          Workspace Name
          <input
            value={draftConfig.workspace.name}
            onChange={(event) =>
              mutateDraft((draft) => {
                draft.workspace.name = event.target.value;
              })
            }
          />
        </label>
        <label>
          Workspace Base Path
          <input
            value={draftConfig.workspace.basePath}
            onChange={(event) =>
              mutateDraft((draft) => {
                draft.workspace.basePath = event.target.value;
              })
            }
          />
        </label>
        <label>
          Auth Token
          <input
            value={draftConfig.auth.token}
            onChange={(event) =>
              mutateDraft((draft) => {
                draft.auth.token = event.target.value;
              })
            }
          />
        </label>
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
        </label>
        <label>
          Memory Provider Mode
          <select
            value={memoryProviderMode}
            onChange={(event) =>
              mutateDraft((draft) => {
                draft.memory.provider.mode = event.target.value;
                if (event.target.value === "local") {
                  draft.memory.provider.endpoint = "";
                  draft.memory.provider.mcpServer = "";
                  draft.memory.provider.apiKeyEnv = "";
                }
              })
            }
          >
            <option value="local">Built-in (Local)</option>
            <option value="http">Remote HTTP</option>
            <option value="mcp">Remote MCP</option>
          </select>
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
        </label>
        <label>
          SQLite Path
          <input
            value={draftConfig.sqlitePath}
            onChange={(event) =>
              mutateDraft((draft) => {
                draft.sqlitePath = event.target.value;
              })
            }
          />
        </label>
        <label>
          Nodes (one per line)
          <textarea
            rows={4}
            value={draftConfig.nodes.join("\n")}
            onChange={(event) =>
              mutateDraft((draft) => {
                draft.nodes = parseLines(event.target.value);
              })
            }
          />
        </label>
        <label>
          Gateways (one per line)
          <textarea
            rows={4}
            value={draftConfig.gateways.join("\n")}
            onChange={(event) =>
              mutateDraft((draft) => {
                draft.gateways = parseLines(event.target.value);
              })
            }
          />
        </label>
      </div>
    </section>
  );
}
