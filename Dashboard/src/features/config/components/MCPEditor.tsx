import React from "react";

function parseHeaders(value) {
  const headers = {};
  String(value || "")
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean)
    .forEach((line) => {
      const separator = line.indexOf(":");
      if (separator <= 0) {
        return;
      }
      const key = line.slice(0, separator).trim();
      const headerValue = line.slice(separator + 1).trim();
      if (key) {
        headers[key] = headerValue;
      }
    });
  return headers;
}

function formatHeaders(headers) {
  return Object.entries(headers || {})
    .map(([key, value]) => `${key}: ${value}`)
    .join("\n");
}

function ensureMCPServer(draft, index, emptyMCPServer) {
  if (!draft.mcp) {
    draft.mcp = { servers: [] };
  }
  if (!Array.isArray(draft.mcp.servers)) {
    draft.mcp.servers = [];
  }
  if (!draft.mcp.servers[index]) {
    draft.mcp.servers[index] = emptyMCPServer();
  }
  return draft.mcp.servers[index];
}

export function MCPEditor({
  draftConfig,
  selectedMCPServerIndex,
  onSelectMCPServerIndex,
  mutateDraft,
  emptyMCPServer,
  parseLines
}) {
  const servers = Array.isArray(draftConfig.mcp?.servers) ? draftConfig.mcp.servers : [];
  const current = servers[selectedMCPServerIndex] || emptyMCPServer();
  const isHTTP = current.transport === "http";

  return (
    <div className="entry-editor-layout">
      <div className="entry-list">
        <div className="entry-list-head">
          <h4>MCP servers</h4>
          <button
            type="button"
            onClick={() => {
              mutateDraft((draft) => {
                if (!draft.mcp) {
                  draft.mcp = { servers: [] };
                }
                if (!Array.isArray(draft.mcp.servers)) {
                  draft.mcp.servers = [];
                }
                draft.mcp.servers.push(emptyMCPServer());
              });
              onSelectMCPServerIndex(servers.length);
            }}
          >
            + Add Server
          </button>
        </div>
        <div className="entry-list-scroll">
          {servers.length === 0 ? (
            <p className="entry-editor-empty">No MCP servers configured.</p>
          ) : null}
          {servers.map((item, index) => (
            <button
              key={`${item.id || "mcp-server"}-${index}`}
              type="button"
              className={`entry-list-item ${index === selectedMCPServerIndex ? "active" : ""}`}
              onClick={() => onSelectMCPServerIndex(index)}
            >
              {item.id || `mcp-server-${index + 1}`}
            </button>
          ))}
        </div>
      </div>

      <section className="entry-editor-card">
        <div className="entry-editor-head">
          <h3>{current.id || "MCP server"}</h3>
          <button
            type="button"
            className="danger"
            disabled={servers.length === 0}
            onClick={() => {
              mutateDraft((draft) => {
                if (!Array.isArray(draft.mcp?.servers)) {
                  return;
                }
                draft.mcp.servers.splice(selectedMCPServerIndex, 1);
              });
            }}
          >
            Delete
          </button>
        </div>

        <section className="entry-editor-block" style={{ marginTop: 0, marginBottom: 10 }}>
          <p className="entry-editor-empty">
            MCP servers add external tools, resources, and prompts for agents. Use stdio for local commands like
            npx packages, or HTTP for hosted MCP endpoints.
          </p>
        </section>

        <div className="entry-form-grid">
          <label>
            Server ID
            <input
              placeholder="filesystem"
              value={current.id}
              onChange={(event) =>
                mutateDraft((draft) => {
                  ensureMCPServer(draft, selectedMCPServerIndex, emptyMCPServer).id = event.target.value;
                })
              }
            />
          </label>
          <label>
            Transport
            <select
              value={current.transport}
              onChange={(event) =>
                mutateDraft((draft) => {
                  const server = ensureMCPServer(draft, selectedMCPServerIndex, emptyMCPServer);
                  server.transport = event.target.value === "http" ? "http" : "stdio";
                })
              }
            >
              <option value="stdio">stdio</option>
              <option value="http">http</option>
            </select>
          </label>
          {isHTTP ? (
            <>
              <label style={{ gridColumn: "1 / -1" }}>
                HTTP Endpoint
                <input
                  placeholder="https://mcp.example.com/v1"
                  value={current.endpoint || ""}
                  onChange={(event) =>
                    mutateDraft((draft) => {
                      ensureMCPServer(draft, selectedMCPServerIndex, emptyMCPServer).endpoint = event.target.value;
                    })
                  }
                />
              </label>
              <label style={{ gridColumn: "1 / -1" }}>
                Headers
                <textarea
                  rows={4}
                  placeholder="Authorization: Bearer token"
                  value={formatHeaders(current.headers)}
                  onChange={(event) =>
                    mutateDraft((draft) => {
                      ensureMCPServer(draft, selectedMCPServerIndex, emptyMCPServer).headers = parseHeaders(event.target.value);
                    })
                  }
                />
                <span className="entry-form-hint">One header per line, formatted as <code>Name: value</code>.</span>
              </label>
            </>
          ) : (
            <>
              <label>
                Command
                <input
                  placeholder="npx"
                  value={current.command || ""}
                  onChange={(event) =>
                    mutateDraft((draft) => {
                      ensureMCPServer(draft, selectedMCPServerIndex, emptyMCPServer).command = event.target.value;
                    })
                  }
                />
              </label>
              <label>
                Working Directory
                <input
                  placeholder="/tmp/workspace"
                  value={current.cwd || ""}
                  onChange={(event) =>
                    mutateDraft((draft) => {
                      ensureMCPServer(draft, selectedMCPServerIndex, emptyMCPServer).cwd = event.target.value;
                    })
                  }
                />
              </label>
              <label style={{ gridColumn: "1 / -1" }}>
                Arguments (one per line)
                <textarea
                  rows={5}
                  placeholder={"-y\n@modelcontextprotocol/server-filesystem\n/tmp/workspace"}
                  value={(current.arguments || []).join("\n")}
                  onChange={(event) =>
                    mutateDraft((draft) => {
                      ensureMCPServer(draft, selectedMCPServerIndex, emptyMCPServer).arguments = parseLines(event.target.value);
                    })
                  }
                />
              </label>
            </>
          )}
          <label>
            Timeout (ms)
            <input
              type="number"
              min="250"
              step="250"
              value={String(current.timeoutMs ?? 15000)}
              onChange={(event) =>
                mutateDraft((draft) => {
                  const parsed = Number.parseInt(event.target.value, 10);
                  ensureMCPServer(draft, selectedMCPServerIndex, emptyMCPServer).timeoutMs = Number.isFinite(parsed)
                    ? Math.max(250, parsed)
                    : 15000;
                })
              }
            />
          </label>
          <label>
            Tool Prefix
            <input
              placeholder="mcp.filesystem"
              value={current.toolPrefix || ""}
              onChange={(event) =>
                mutateDraft((draft) => {
                  ensureMCPServer(draft, selectedMCPServerIndex, emptyMCPServer).toolPrefix = event.target.value;
                })
              }
            />
          </label>
          <label>
            Enabled
            <select
              value={current.enabled ? "enabled" : "disabled"}
              onChange={(event) =>
                mutateDraft((draft) => {
                  ensureMCPServer(draft, selectedMCPServerIndex, emptyMCPServer).enabled = event.target.value === "enabled";
                })
              }
            >
              <option value="enabled">Enabled</option>
              <option value="disabled">Disabled</option>
            </select>
          </label>
          <label>
            Expose Tools
            <select
              value={current.exposeTools ? "yes" : "no"}
              onChange={(event) =>
                mutateDraft((draft) => {
                  ensureMCPServer(draft, selectedMCPServerIndex, emptyMCPServer).exposeTools = event.target.value === "yes";
                })
              }
            >
              <option value="yes">Yes</option>
              <option value="no">No</option>
            </select>
          </label>
          <label>
            Expose Resources
            <select
              value={current.exposeResources ? "yes" : "no"}
              onChange={(event) =>
                mutateDraft((draft) => {
                  ensureMCPServer(draft, selectedMCPServerIndex, emptyMCPServer).exposeResources = event.target.value === "yes";
                })
              }
            >
              <option value="yes">Yes</option>
              <option value="no">No</option>
            </select>
          </label>
          <label>
            Expose Prompts
            <select
              value={current.exposePrompts ? "yes" : "no"}
              onChange={(event) =>
                mutateDraft((draft) => {
                  ensureMCPServer(draft, selectedMCPServerIndex, emptyMCPServer).exposePrompts = event.target.value === "yes";
                })
              }
            >
              <option value="yes">Yes</option>
              <option value="no">No</option>
            </select>
          </label>
        </div>
      </section>
    </div>
  );
}
