//
//  Errors.swift
//  ACPModel
//
//  Agent Client Protocol - Error Types
//

import Foundation

public enum ClientError: Error, LocalizedError, Sendable {
    case processNotRunning
    case processFailed(Int32)
    case invalidResponse
    case requestTimeout
    case encodingError
    case decodingError(Error)
    case agentError(JSONRPCError)
    case delegateNotSet
    case fileNotFound(String)
    case fileOperationFailed(String)
    case transportError(String)
    case connectionClosed

    public var errorDescription: String? {
        switch self {
        case .processNotRunning:
            return "Agent process is not running"
        case .processFailed(let code):
            return "Agent process failed with exit code \(code)"
        case .invalidResponse:
            return "Invalid response from agent"
        case .requestTimeout:
            return "Request timed out"
        case .encodingError:
            return "Failed to encode request"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .agentError(let jsonError):
            if let dataString = jsonError.data?.value as? String {
                return dataString
            }

            if let data = jsonError.data?.value as? [String: Any],
               let details = data["details"] as? String {
                if let detailsData = details.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: detailsData) as? [String: Any],
                   let error = json["error"] as? [String: Any],
                   let message = error["message"] as? String {
                    return message
                }
                return details
            }

            return jsonError.message
        case .delegateNotSet:
            return "Internal error: Delegate not set"
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .fileOperationFailed(let message):
            return "File operation failed: \(message)"
        case .transportError(let message):
            return "Transport error: \(message)"
        case .connectionClosed:
            return "Connection closed"
        }
    }
}

// MARK: - Typealiases for backward compatibility

@available(*, deprecated, renamed: "ClientError")
public typealias ACPClientError = ClientError
