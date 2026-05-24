import React from "react";

const MEMORY_PROVIDER_MODES = [
  { value: "local", label: "Built-in (Local)", description: "Use Sloppy's built-in local memory provider." },
  { value: "http", label: "Remote HTTP", description: "Call an external HTTP memory provider." },
  { value: "mcp", label: "Remote MCP", description: "Route memory operations through an MCP server." }
];

export function NodeHostEditor({ draftConfig, mutateDraft, parseLines }) {
  const memoryProviderMode = String(draftConfig.memory?.provider?.mode || "local");
  const memoryProviderOption = MEMORY_PROVIDER_MODES.find((option) => option.value === memoryProviderMode) || MEMORY_PROVIDER_MODES[0];
  const [memoryProviderMenuOpen, setMemoryProviderMenuOpen] = React.useState(false);
  const [nodeTestStatus, setNodeTestStatus] = React.useState({});
  const [selectedNodeIndex, setSelectedNodeIndex] = React.useState(0);
  const nodes = Array.isArray(draftConfig.nodes) ? draftConfig.nodes : [];
  const selectedNode = nodes[selectedNodeIndex] || nodes[0] || null;
  const selectedNodeStatus = selectedNode ? nodeStatus(selectedNode) : { label: "empty", tone: "off" };

  React.useEffect(() => {
    if (selectedNodeIndex >= nodes.length) {
      setSelectedNodeIndex(Math.max(0, nodes.length - 1));
    }
  }, [nodes.length, selectedNodeIndex]);

  function parseInteger(value, fallback) {
    const parsed = Number.parseInt(value, 10);
    return Number.isFinite(parsed) ? parsed : fallback;
  }

  function updateNode(index, patch) {
    mutateDraft((draft) => {
      if (!Array.isArray(draft.nodes)) {
        draft.nodes = [];
      }
      draft.nodes[index] = { ...draft.nodes[index], ...patch };
    });
  }

  function addNode() {
    const nextIndex = nodes.length;
    mutateDraft((draft) => {
      if (!Array.isArray(draft.nodes)) {
        draft.nodes = [];
      }
      draft.nodes.push({
        id: `remote-${nextIndex + 1}`,
        title: "",
        url: "",
        token: "",
        tokenEnv: "",
        enabled: true,
        kind: "sloppy_instance"
      });
    });
    setSelectedNodeIndex(nextIndex);
  }

  function removeNode(index) {
    mutateDraft((draft) => {
      draft.nodes.splice(index, 1);
    });
    setSelectedNodeIndex((current) => Math.max(0, Math.min(current, nodes.length - 2)));
    setNodeTestStatus((current) => {
      const next = {};
      Object.entries(current).forEach(([key, value]) => {
        const parsed = Number.parseInt(key, 10);
        if (parsed < index) {
          next[parsed] = value;
        } else if (parsed > index) {
          next[parsed - 1] = value;
        }
      });
      return next;
    });
  }

  function nodeTitle(node, index) {
    return String(node?.title || node?.id || `remote-${index + 1}`).trim();
  }

  function nodeSubtitle(node) {
    if (!node) {
      return "No instance selected";
    }
    if (node.kind === "local" && !node.url) {
      return "Current local runtime";
    }
    return node.url || "Remote URL is not set";
  }

  function nodeStatus(node) {
    if (!node) {
      return { label: "empty", tone: "off" };
    }
    if (node.enabled === false) {
      return { label: "disabled", tone: "off" };
    }
    if (node.kind === "local" && !node.url) {
      return { label: "local", tone: "on" };
    }
    return node.url ? { label: "remote", tone: "on" } : { label: "draft", tone: "off" };
  }

  function nodeAuthValue(node) {
    if (node?.tokenEnv) {
      return `env:${node.tokenEnv}`;
    }
    return node?.token || "";
  }

  function parseNodeAuthValue(value) {
    const trimmed = String(value || "").trim();
    if (trimmed.toLowerCase().startsWith("env:")) {
      return { token: "", tokenEnv: trimmed.slice(4).trim() };
    }
    if (/^\$[A-Z_][A-Z0-9_]*$/.test(trimmed)) {
      return { token: "", tokenEnv: trimmed.slice(1) };
    }
    return { token: value, tokenEnv: "" };
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
      if (!token && node?.tokenEnv) {
        setNodeTestStatus((current) => ({
          ...current,
          [index]: `Health OK · token comes from env:${node.tokenEnv} at runtime`
        }));
        return;
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
    <div className="tg-settings-shell nodehost-settings-shell">
      <section className="entry-editor-card providers-intro-card">
        <h3>NodeHost & Runtime</h3>
        <p className="placeholder-text">
          Configure the local Core API, persistence paths, memory backend, and linked Sloppy instances used by the TUI remote picker.
        </p>
      </section>

      <section className="entry-editor-card">
        <h3>Local Runtime</h3>
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
            <span className="entry-form-hint">Network interface for the local Core API. Use 127.0.0.1 for local-only access.</span>
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
            <span className="entry-form-hint">HTTP port for the local Core API and dashboard backend.</span>
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
            <span className="entry-form-hint">Directory name Sloppy uses for workspace metadata.</span>
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
            <span className="entry-form-hint">Base directory for Sloppy workspace data. Home shortcuts like ~ are supported.</span>
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
            <span className="entry-form-hint">Bearer token expected by this local Core API.</span>
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
            <span className="entry-form-hint">Path to the Core SQLite database.</span>
          </label>
        </div>
      </section>

      <div className="entry-editor-layout config-integration-layout config-node-layout">
        <div className="entry-list config-integration-list">
          <div className="entry-list-head">
            <h4>Sloppy instances</h4>
            <button type="button" className="config-integration-add-button" onClick={addNode}>
              <span className="material-symbols-rounded" aria-hidden>
                add
              </span>
              <span>Add</span>
            </button>
          </div>
          <div className="entry-list-scroll">
            {nodes.length === 0 ? (
              <p className="entry-editor-empty config-integration-empty">No linked Sloppy instances configured.</p>
            ) : null}
            {nodes.map((node, index) => {
              const status = nodeStatus(node);
              return (
                <button
                  key={`node-${index}`}
                  type="button"
                  className={`entry-list-item config-integration-list-item ${index === selectedNodeIndex ? "active" : ""}`}
                  onClick={() => setSelectedNodeIndex(index)}
                >
                  <span className="providers-cli-card-icon material-symbols-rounded" aria-hidden>
                    hub
                  </span>
                  <span className="config-integration-list-main">
                    <span className="config-integration-list-title">{nodeTitle(node, index)}</span>
                    <span className="config-integration-list-subtitle">{nodeSubtitle(node)}</span>
                    <span className={`provider-state ${status.tone}`}>{status.label}</span>
                  </span>
                </button>
              );
            })}
          </div>
        </div>

        <section className="entry-editor-card config-integration-card">
          <div className="entry-editor-head config-integration-head">
            <div className="config-integration-title-row">
              <span className="provider-list-icon" aria-hidden="true">
                <span className="material-symbols-rounded">hub</span>
              </span>
              <div className="config-integration-heading">
                <h3>{selectedNode ? nodeTitle(selectedNode, selectedNodeIndex) : "Sloppy instance"}</h3>
                <span className="provider-model-line">{selectedNode ? nodeSubtitle(selectedNode) : "Add an instance to edit it"}</span>
              </div>
              <span className={`provider-state ${selectedNodeStatus.tone}`}>{selectedNodeStatus.label}</span>
            </div>
            <button
              type="button"
              className="danger"
              disabled={!selectedNode}
              onClick={() => removeNode(selectedNodeIndex)}
            >
              Delete
            </button>
          </div>

          <section className="entry-editor-block config-integration-note">
            <p className="entry-editor-empty">
              Linked instances appear in the TUI <code>/remote</code> picker. Use a direct token for browser-side connection tests,
              or <code>env:SLOPPY_REMOTE_TOKEN</code> to have Sloppy resolve the token from the runtime environment.
            </p>
          </section>

          {selectedNode ? (
            <div className="entry-form-grid">
              <label>
                ID
                <input
                  value={selectedNode.id || ""}
                  onChange={(event) => updateNode(selectedNodeIndex, { id: event.target.value })}
                />
                <span className="entry-form-hint">Stable config identifier used by the TUI. Keep it lowercase and unique.</span>
              </label>
              <label>
                Title
                <input
                  value={selectedNode.title || ""}
                  onChange={(event) => updateNode(selectedNodeIndex, { title: event.target.value })}
                />
                <span className="entry-form-hint">Human-friendly name shown in pickers and settings.</span>
              </label>
              <label>
                URL
                <input
                  placeholder="https://sloppy.example.com:25101"
                  value={selectedNode.url || ""}
                  onChange={(event) => updateNode(selectedNodeIndex, { url: event.target.value, kind: "sloppy_instance" })}
                />
                <span className="entry-form-hint">Base URL of the remote Core API, without a trailing path.</span>
              </label>
              <label>
                Token
                <input
                  placeholder="dev-token or env:SLOPPY_REMOTE_TOKEN"
                  value={nodeAuthValue(selectedNode)}
                  onChange={(event) => updateNode(selectedNodeIndex, parseNodeAuthValue(event.target.value))}
                />
                <span className="entry-form-hint">
                  Enter a bearer token directly, or prefix an environment variable with <code>env:</code>.
                </span>
              </label>
              <label>
                Runtime
                <div className="config-field-toggle">
                  <span>{selectedNode.enabled !== false ? "Enabled" : "Disabled"}</span>
                  <span className="agent-tools-switch">
                    <input
                      type="checkbox"
                      checked={selectedNode.enabled !== false}
                      onChange={(event) => updateNode(selectedNodeIndex, { enabled: event.target.checked })}
                    />
                    <span className="agent-tools-switch-track" />
                  </span>
                </div>
                <span className="entry-form-hint">Disabled instances stay in config but are hidden from the TUI remote picker.</span>
              </label>
              <div className="config-node-test">
                <button type="button" onClick={() => testNode(selectedNode, selectedNodeIndex)}>
                  Test connection
                </button>
                {nodeTestStatus[selectedNodeIndex] ? <span>{nodeTestStatus[selectedNodeIndex]}</span> : null}
              </div>
            </div>
          ) : null}
        </section>
      </div>

      <section className="entry-editor-card">
        <h3>Gateways</h3>
        <div className="entry-form-grid">
          <label style={{ gridColumn: "1 / -1" }}>
            Gateway IDs
            <textarea
              rows={4}
              value={draftConfig.gateways.join("\n")}
              onChange={(event) =>
                mutateDraft((draft) => {
                  draft.gateways = parseLines(event.target.value);
                })
              }
            />
            <span className="entry-form-hint">
              Optional runtime gateway/plugin identifiers to enable at startup, one per line. Leave empty when channel plugins are managed elsewhere.
            </span>
          </label>
        </div>
      </section>
    </div>
  );
}
