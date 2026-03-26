[Tools usage rules]
- All available tools are registered as native function calls. Use them directly without calling `system.list_tools` first.
- Only call `system.list_tools` if you need to discover dynamically added MCP tools.
- When using a tool, follow its parameter schema exactly. Required parameters must be provided.
