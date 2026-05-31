//
//  ACPModel.swift
//  ACPModel
//
//  Agent Client Protocol - Model Types
//
//  This module contains all ACP protocol data types that can be
//  shared between client and agent implementations.
//

import Foundation

// Re-export all public types for convenient access
// All types are defined in their respective files:
// - Message.swift: JSON-RPC message types, AnyCodable, RequestId
// - Session.swift: SessionId, ClientInfo, AgentInfo, StopReason, etc.
// - Content.swift: ContentBlock, TextContent, ImageContent, etc.
// - Tool.swift: ToolCall, ToolKind, ToolStatus, Plan, etc.
// - Updates.swift: SessionUpdate, ToolCallUpdate, etc.
// - Capabilities.swift: ClientCapabilities, AgentCapabilities, etc.
// - Config.swift: SessionConfigOption, SessionConfigKind, etc.
// - Terminal.swift: TerminalId, EnvVariable, terminal request/response types
// - Permission.swift: RequestPermissionRequest, PermissionOutcome, etc.
// - Requests.swift: InitializeRequest, NewSessionRequest, etc.
// - Responses.swift: InitializeResponse, NewSessionResponse, etc.
// - Errors.swift: ClientError enum
