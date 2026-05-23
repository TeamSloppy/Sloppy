import React from "react";

export function NodeHostEditor({ draftConfig, mutateDraft, parseLines }) {
  const memoryProviderMode = String(draftConfig.memory?.provider?.mode || "local");
  const [nodeTestStatus, setNodeTestStatus] = React.useState({});

  function parseInteger(value, fallback) {
    const parsed = Number.parseInt(value, 10);
    return Number.isFinite(parsed) ? parsed : fallback;
  }

  function updateNode(index, patch) {
    mutateDraft((draft) => {
      draft.nodes[index] = { ...draft.nodes[index], ...patch };
    });
  }

  function addNode() {
    mutateDraft((draft) => {
      const nextIndex = Array.isArray(draft.nodes) ? draft.nodes.length + 1 : 1;
      draft.nodes.push({
        id: `remote-${nextIndex}`,
        title: "",
        url: "",
        token: "",
        tokenEnv: "",
        enabled: true,
        kind: "sloppy_instance"
      });
    });
  }

  function removeNode(index) {
    mutateDraft((draft) => {
      draft.nodes.splice(index, 1);
    });
  }

  async function testNode(node, index) {
    const baseURL = String(node?.url || "").replace(/\/+$/, "");
    const token = String(node?.token || "").trim();
    if (!baseURL) {
      setNodeTestStatus((current) => ({ ...current, [index]: "Enter a URL first." }));
      return;
    }
    setNodeTestStatus((current) => ({ ...current, [index]: "Testing..." }));
    try {
      const healthResponse = await fetch(`${baseURL}/health`);
      if (!healthResponse.ok) {
        throw new Error(`Health returned ${healthResponse.status}`);
      }
      const headers = token ? { Authorization: `Bearer ${token}` } : {};
      const projectsResponse = await fetch(`${baseURL}/v1/projects`, { headers });
      if (!projectsResponse.ok) {
        throw new Error(`Projects returned ${projectsResponse.status}`);
      }
      const projects = await projectsResponse.json();
      const count = Array.isArray(projects) ? projects.length : 0;
      setNodeTestStatus((current) => ({ ...current, [index]: `Connected · ${count} projects` }));
    } catch (error) {
      const message = error instanceof Error ? error.message : "Connection failed";
      setNodeTestStatus((current) => ({ ...current, [index]: message }));
    }
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
        <div className="config-node-list">
          <div className="config-node-list-head">
            <span>Sloppy Instances</span>
            <button type="button" className="config-integration-add-button" onClick={addNode}>
              Add instance
            </button>
          </div>
          {(draftConfig.nodes || []).map((node, index) => {
            const isLocal = node.kind === "local";
            const status = nodeTestStatus[index];
            return (
              <section className="config-node-entry" key={`${node.id}-${index}`}>
                <div className="config-node-entry-top">
                  <label className="config-field-toggle">
                    <input
                      type="checkbox"
                      checked={node.enabled !== false}
                      disabled={isLocal}
                      onChange={(event) => updateNode(index, { enabled: event.target.checked })}
                    />
                    Enabled
                  </label>
                  <span className="config-node-kind">{node.kind || "sloppy_instance"}</span>
                  {!isLocal ? (
                    <button type="button" className="entry-danger-button" onClick={() => removeNode(index)}>
                      Delete
                    </button>
                  ) : null}
                </div>
                <div className="entry-form-grid">
                  <label>
                    ID
                    <input
                      value={node.id || ""}
                      disabled={isLocal}
                      onChange={(event) => updateNode(index, { id: event.target.value })}
                    />
                  </label>
                  <label>
                    Title
                    <input
                      value={node.title || ""}
                      disabled={isLocal}
                      onChange={(event) => updateNode(index, { title: event.target.value })}
                    />
                  </label>
                  <label>
                    URL
                    <input
                      placeholder="https://sloppy.example.com:25101"
                      value={node.url || ""}
                      disabled={isLocal}
                      onChange={(event) => updateNode(index, { url: event.target.value, kind: "sloppy_instance" })}
                    />
                  </label>
                  <label>
                    Token
                    <input
                      value={node.token || ""}
                      disabled={isLocal}
                      onChange={(event) => updateNode(index, { token: event.target.value })}
                    />
                  </label>
                  <label>
                    Token Env
                    <input
                      placeholder="SLOPPY_REMOTE_TOKEN"
                      value={node.tokenEnv || ""}
                      disabled={isLocal}
                      onChange={(event) => updateNode(index, { tokenEnv: event.target.value })}
                    />
                  </label>
                  <div className="config-node-test">
                    <button type="button" disabled={isLocal} onClick={() => testNode(node, index)}>
                      Test connection
                    </button>
                    {status ? <span>{status}</span> : null}
                  </div>
                </div>
              </section>
            );
          })}
        </div>
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
