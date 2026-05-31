//
//  Errors.swift
//  ACP
//
//  Error handling for ACP client
//

import Foundation
import ACPModel

// ClientError is now defined in ACPModel
// This file contains the ErrorHandler actor which is ACP-specific

actor ErrorHandler {
    // MARK: - Properties

    private let encoder: JSONEncoder

    // MARK: - Initialization

    init(encoder: JSONEncoder) {
        self.encoder = encoder
    }

    // MARK: - Error Response Creation

    func createErrorResponse(
        requestId: RequestId,
        code: Int,
        message: String
    ) throws -> JSONRPCResponse {
        let error = JSONRPCError(code: code, message: message, data: nil)
        return JSONRPCResponse(id: requestId, result: nil, error: error)
    }

    // MARK: - Error Handling

    func handleError(_ error: Error) -> String {
        if let clientError = error as? ClientError {
            return clientError.errorDescription ?? error.localizedDescription
        }
        return error.localizedDescription
    }

    func extractAgentError(from response: JSONRPCResponse) -> Error? {
        if let error = response.error {
            return ClientError.agentError(error)
        }
        return nil
    }
}
