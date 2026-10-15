# MCP Swift SDK for Windows

Source: https://github.com/modelcontextprotocol/swift-sdk, tag `0.12.1`,
revision `a0ae212ebf6eab5f754c3129608bc5557637e605` (MIT; see LICENSE).

Only `Sources/MCP` is vendored. The root package uses this copy on Windows;
Apple and Linux builds continue to use the upstream package dependency.

Local changes:

- The package manifest exposes the MCP library without upstream examples or documentation plugins.
- HTTPClientTransport applies the upstream FoundationNetworking path to Windows as well as Linux,
  because neither provides URLSession.AsyncBytes. Its SSE limitation applies to both platforms.
- Sloppy supplies its Windows pipe transport in Sources/sloppy/MCP/WindowsStdioTransport.swift.
