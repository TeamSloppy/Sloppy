# Skills and MCP Tooling Spec

## 1. Document Status
- Version: `0.1`
- Date: `2026-06-03`
- Status: `Draft for product and implementation alignment`
- Owners: `sloppy`, `PluginSDK`, `Dashboard`
- Primary code areas: `Sources/sloppy/CoreService+Skills.swift`, `Sources/sloppy/CoreService+MCP.swift`, `Sources/sloppy/Gateway/Routers/SkillsAPIRouter.swift`, `Sources/sloppy/CLI/Commands/SkillsCommands.swift`, `Sources/sloppy/CLI/Commands/MCPCommands.swift`, `Dashboard/src/api.ts`

## 2. Product Context
Sloppy extends agent capabilities through installed skills and configured MCP servers. Skills provide reusable instructions, prompts, model preferences, slash commands, and potentially local assets. MCP servers expose external tools, resources, and prompts over stdio or HTTP. Together they make agents extensible without changing the core runtime for every integration.

## 3. Goals
1. Let operators discover, install, list, and uninstall skills for an agent.
2. Let operators configure MCP servers and expose tools/resources/prompts to agents.
3. Merge built-in tools, skill-provided affordances, plugin tools, and MCP tools into one policy-aware catalog.
4. Keep tool names stable and provider-safe through sanitization.
5. Make install/configuration failures explicit and recoverable.

## 4. Non-goals
1. Running untrusted arbitrary code without sandboxing or user approval.
2. Guaranteeing every MCP server is compatible with every model/tool-calling format.
3. Treating skills as full package managers for binary dependencies.
4. Allowing skills to bypass configured tool approval policy.

## 5. Core Concepts
| Concept | Description |
| --- | --- |
| Skill | Installed directory or registry/GitHub package with `SKILL.md` metadata and instructions. |
| Registry | Searchable source of skill entries sorted by installs, trending, or recency. |
| MCP server | External server reachable by stdio command or HTTP endpoint. |
| Exposed capability | Tool, prompt, or resource made available from an MCP server. |
| Tool prefix | Optional namespace prefix to prevent capability name collisions. |
| Tool policy | Agent-level authorization and approval rules applied after catalog construction. |

## 6. Functional Requirements

### FR-1: Skill discovery
- Clients can search the skill registry by query, sort, limit, and offset.
- Results include enough metadata for an operator to decide whether to install.

### FR-2: Skill installation
- A skill can be installed from registry/GitHub or local path.
- Install reads and validates `SKILL.md` frontmatter and body.
- Skill preferred model metadata can influence worker/session model selection only when allowed by agent/runtime policy.

### FR-3: Skill lifecycle per agent
- Clients can list installed skills for an agent.
- Clients can uninstall a skill by skill ID.
- Missing or corrupted skill files should be reported without breaking the full agent catalog.

### FR-4: MCP server configuration
- Operators can add/update/remove MCP servers with transport, command/arguments or endpoint, headers, timeout, and exposure toggles.
- Server config supports `exposeTools`, `exposePrompts`, `exposeResources`, and optional `toolPrefix`.
- Install/uninstall commands may run before saving/removing config when explicitly requested.

### FR-5: MCP capability access
- Clients can list tools, prompts, and resources for a configured server.
- Clients can call a tool, get a prompt, and read a resource through the core runtime.
- Timeouts and server errors must return structured failures.

### FR-6: Catalog merge and sanitization
- Tool names from all sources are sanitized for model compatibility.
- Collisions are resolved by namespacing, prefixing, or deterministic rejection with an actionable error.
- Tool policy filters the final catalog before exposure to an agent session.

### FR-7: Security and approvals
- Stdio MCP commands and install commands are potentially dangerous and should be subject to explicit operator action.
- Sensitive headers and environment-derived secrets must be redacted in API responses and logs.
- Tool calls still pass through normal approval and loop-guard services.

## 7. Public API / Tool Surface
Representative API endpoints and tool functions:
- `GET /v1/skills/registry`
- `GET /v1/agents/{agentId}/skills`
- `POST /v1/agents/{agentId}/skills`
- `DELETE /v1/agents/{agentId}/skills/{skillId}`
- `GET /v1/agents/{agentId}/tools/catalog`
- `PUT /v1/agents/{agentId}/tools`
- `POST /v1/agents/{agentId}/tools/invoke`
- MCP management tools: `mcp_save_server`, `mcp_install_server`, `mcp_remove_server`, `mcp_uninstall_server`
- MCP access tools: `mcp_list_tools`, `mcp_call_tool`, `mcp_list_prompts`, `mcp_get_prompt`, `mcp_list_resources`, `mcp_read_resource`

## 8. Dashboard UX
1. Agent configuration shows installed skills and lets users install/uninstall when supported.
2. Tool catalog view shows source, name, description, policy state, and approval requirement.
3. MCP server configuration should make transport-specific fields clear.
4. Errors should distinguish install failure, server startup failure, list failure, and tool invocation failure.

## 9. Edge Cases
- Registry search may be unavailable; local installs should still work.
- A stdio MCP server may hang on startup; timeout must be enforced.
- Two servers may expose the same tool name; collision handling must be deterministic.
- A skill with invalid frontmatter should not poison other installed skills.
- Uninstalling a skill while a session is running should affect future catalog builds, not mutate an in-flight tool call.

## 10. Acceptance Criteria
1. An operator can search for a skill, install it for an agent, list it, and uninstall it.
2. An operator can save an MCP server, list its tools, call one tool, and remove the server.
3. Tool catalog includes source metadata and respects tool policy.
4. Invalid MCP server config produces a structured error without crashing the runtime.
5. Secret headers are not exposed in API responses or logs.

## 11. Tests / Verification
- Backend: skills registry service, skill frontmatter, MCP status/config, tool registry, tool name sanitizer, tool approval and loop guard tests.
- Manual: configure a known MCP stdio server, expose one tool, call it from an agent session, then disable exposure and verify catalog update.
