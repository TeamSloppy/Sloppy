# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Swift SDK for the Agent Client Protocol (ACP). This library enables Swift applications to communicate with ACP-compliant coding agents (like Claude Code) via JSON-RPC over stdio.

## Build & Test Commands

```bash
# Build
swift build

# Run all tests
swift test

# Run specific test file
swift test --filter ACPClientTests

# Run single test
swift test --filter ACPClientTests.testSessionIdEncoding
```

## Architecture

### Core Components

**ACPClient** (`Sources/ACP/Client/ACPClient.swift`)
- Main entry point, actor-based for thread safety
- Manages agent lifecycle: launch → initialize → newSession → sendPrompt → terminate
- Exposes `notifications` AsyncStream for session updates
- Optional `debugMessages` stream for raw JSON-RPC traffic

**ACPProcessManager** (`Sources/ACP/Client/ACPProcessManager.swift`)
- Handles subprocess lifecycle and stdio pipes
- Parses newline-delimited JSON from stdout using bracket-counting parser
- Manages process groups for clean termination (SIGTERM then SIGKILL)

**ACPRequestRouter** (`Sources/ACP/Client/ACPRequestRouter.swift`)
- Routes incoming JSON-RPC requests from agent to delegate methods
- Supports: fs/read_text_file, fs/write_text_file, terminal/*, request_permission

### Delegate Pattern

Implement `ACPClientDelegate` to handle agent requests:
- File operations: `handleFileReadRequest`, `handleFileWriteRequest`
- Terminal operations: `handleTerminalCreate`, `handleTerminalOutput`, `handleTerminalWaitForExit`, `handleTerminalKill`, `handleTerminalRelease`
- Permissions: `handlePermissionRequest`

Default implementations: `ACPFileSystemDelegate`, `ACPTerminalDelegate`

### Models

- `Sources/ACP/Message.swift` - JSON-RPC primitives (Message enum), AnyCodable helper
- `Sources/ACP/Session.swift` - Session IDs, capabilities, client/agent info
- `Sources/ACP/Updates.swift` - Streaming updates (agent_message_chunk, tool_call, etc.)
- `Sources/ACP/Content.swift` - ContentBlock (text, image, etc.)
- `Sources/ACP/Tool.swift` - ToolCall, ToolKind, ToolStatus, Plan

### Key Types

- `SessionId`, `TerminalId`, `RequestId` - Type-safe identifiers
- `ContentBlock` - Enum for text/image content
- `SessionUpdate` - Streaming session state changes
- `ToolCall` - Agent tool invocations with kind, status, content

## Protocol Reference

- `reference/agent-client-protocol/` - ACP specification
- `reference/rust-sdk/` - Reference Rust implementation

## Swift Concurrency

All public APIs are async. ACPClient and ACPProcessManager are actors. Types are Sendable.
