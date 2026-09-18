# Agent Plugins v1

An Agent Plugin is a versioned ZIP bundle installed by Sloppy Core. The archive must contain
`agent-plugin.json` at its root. Package identifiers use `scope.name`; versions use SemVer.

## Minimal package

```json
{
  "schemaVersion": 1,
  "id": "acme.review-tools",
  "name": "Review Tools",
  "version": "1.0.0",
  "inputs": [],
  "components": {
    "skills": [{ "id": "review", "path": "skills/review" }],
    "mcpServers": [],
    "sloppyPlugins": [],
    "software": []
  }
}
```

Skill paths point to directories containing `SKILL.md`. Sloppy plugin paths point to existing
source-plugin roots containing `plugin.json`. MCP definitions use the same stdio/HTTP fields as
Sloppy configuration and are installed with IDs namespaced by the package ID.

Inputs have `id`, `title`, `kind` (`string`, `boolean`, `choice`, or `secret`), `required`, optional
`defaultValue`, and optional `choices`. `${input.id}` and `${secret.id}` are the only substitutions.
Secret substitutions are accepted for approved installation commands, but not for persisted MCP
configuration; MCP credentials should reference environment variables already provided to Core.

Software steps contain explicit `executable`, `arguments`, optional `cwd`, `environment`, and
`timeoutSeconds`. Every software component must declare both `uninstall` and `rollback`. Sloppy does
not provide a TTY or elevate privileges. The exact install commands form part of the immutable plan
the administrator approves.

## Registry v1

A registry is a public HTTPS service:

- `GET /v1/packages?query=&cursor=&limit=` returns `AgentPluginCatalogResponse`.
- `GET /v1/packages/{scope}/{name}` returns one `AgentPluginCatalogItem` with releases.
- Each release provides `version`, HTTPS `downloadURL`, SHA-256, byte size, compatibility metadata,
  and prerelease state.

Registry ZIPs must match their published SHA-256. Direct URL and uploaded ZIP sources are shown as
unverified and require an explicit trust confirmation. Publishing, private-registry authentication,
dependency resolution, and automatic updates are outside v1.

## Lifecycle

Clients call upload/inspection, submit selected agent IDs and input values for a plan, display the
complete plan, then execute it with the exact approval hash. Inspections and plans expire after 15
minutes. Installed ownership and hashes are persisted by Core so uninstall can detect modified
components before deleting them.
