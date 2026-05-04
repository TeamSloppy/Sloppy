import Foundation
import AgentRuntime
import Protocols

struct ChannelsAPIRouter: APIRouter {
    private let service: CoreService

    init(service: CoreService) {
        self.service = service
    }

    func configure(on router: CoreRouterRegistrar) {
        router.get("/v1/channels/:channelId/state", metadata: RouteMetadata(summary: "Get channel state", description: "Returns the current state of a communication channel", tags: ["Channels"])) { request in
            let channelId = request.pathParam("channelId") ?? ""
            let state = await service.getChannelState(channelId: channelId) ?? ChannelSnapshot(
                channelId: channelId,
                messages: [],
                contextUtilization: 0,
                activeWorkerIds: [],
                lastDecision: nil
            )
            return CoreRouter.encodable(status: HTTPStatus.ok, payload: state)
        }

        router.get("/v1/channels/:channelId/events", metadata: RouteMetadata(summary: "List channel events", description: "Returns a paginated list of events for a specific channel", tags: ["Channels"])) { request in
            let channelId = request.pathParam("channelId") ?? ""
            let parsedLimit = Int(request.queryParam("limit") ?? "") ?? 50
            let limit = max(1, min(parsedLimit, 200))
            let cursor = request.queryParam("cursor")
            let before = request.queryParam("before").flatMap { CoreRouter.isoDate(from: $0) }
            let after = request.queryParam("after").flatMap { CoreRouter.isoDate(from: $0) }
            let response = await service.listChannelEvents(
                channelId: channelId,
                limit: limit,
                cursor: cursor,
                before: before,
                after: after
            )
            return CoreRouter.encodable(status: HTTPStatus.ok, payload: response)
        }

        router.post("/v1/channels/:channelId/messages", metadata: RouteMetadata(summary: "Post channel message", description: "Sends a new message to a specific channel", tags: ["Channels"])) { request in
            let channelId = request.pathParam("channelId") ?? ""
            guard let body = request.body,
                  let payload = CoreRouter.decode(body, as: ChannelMessageRequest.self)
            else {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidBody])
            }

            let decision = await service.postChannelMessage(channelId: channelId, request: payload)
            return CoreRouter.encodable(status: HTTPStatus.ok, payload: decision)
        }

        router.get("/v1/channels/:channelId/model", metadata: RouteMetadata(summary: "Get channel model", description: "Returns the current model override and available models for a channel", tags: ["Channels"])) { request in
            let channelId = request.pathParam("channelId") ?? ""
            let response = await service.getChannelModel(channelId: channelId)
            return CoreRouter.encodable(status: HTTPStatus.ok, payload: response)
        }

        router.put("/v1/channels/:channelId/model", metadata: RouteMetadata(summary: "Set channel model", description: "Sets the model override for a channel", tags: ["Channels"])) { request in
            let channelId = request.pathParam("channelId") ?? ""
            guard let body = request.body,
                  let payload = CoreRouter.decode(body, as: ChannelModelUpdateRequest.self)
            else {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidBody])
            }

            do {
                let response = try await service.setChannelModel(channelId: channelId, model: payload.model)
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: response)
            } catch {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidAgentModel])
            }
        }

        router.delete("/v1/channels/:channelId/model", metadata: RouteMetadata(summary: "Clear channel model", description: "Removes the model override for a channel, reverting to default", tags: ["Channels"])) { request in
            let channelId = request.pathParam("channelId") ?? ""
            await service.removeChannelModel(channelId: channelId)
            return CoreRouter.json(status: HTTPStatus.ok, payload: [:] as [String: String])
        }

        router.post("/v1/channels/:channelId/control", metadata: RouteMetadata(summary: "Control channel", description: "Sends a control command (abort/interrupt) to a channel's active processing", tags: ["Channels"])) { request in
            let channelId = request.pathParam("channelId") ?? ""
            guard let body = request.body,
                  let payload = CoreRouter.decode(body, as: ChannelControlRequest.self)
            else {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidBody])
            }

            let response = await service.controlChannel(channelId: channelId, action: payload.action)
            return CoreRouter.encodable(status: HTTPStatus.ok, payload: response)
        }

        router.post("/v1/channels/:channelId/route/:workerId", metadata: RouteMetadata(summary: "Route channel to worker", description: "Routes a specific channel to a worker", tags: ["Channels"])) { request in
            let channelId = request.pathParam("channelId") ?? ""
            let workerId = request.pathParam("workerId") ?? ""
            guard let body = request.body,
                  let payload = CoreRouter.decode(body, as: ChannelRouteRequest.self)
            else {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidBody])
            }

            let accepted = await service.postChannelRoute(
                channelId: channelId,
                workerId: workerId,
                request: payload
            )
            return CoreRouter.encodable(
                status: accepted ? HTTPStatus.ok : HTTPStatus.notFound,
                payload: AcceptResponse(accepted: accepted)
            )
        }

        router.get("/v1/tool-approvals/pending", metadata: RouteMetadata(summary: "List pending tool approvals", description: "Returns pending human approval requests for risky tool calls", tags: ["Tools"])) { _ in
            let pending = await service.listPendingToolApprovals()
            return CoreRouter.encodable(status: HTTPStatus.ok, payload: pending)
        }

        router.post("/v1/tool-approvals/:approvalId/approve", metadata: RouteMetadata(summary: "Approve tool call", description: "Approves a pending risky tool call", tags: ["Tools"])) { request in
            let approvalId = request.pathParam("approvalId") ?? ""
            let payload = request.body.flatMap { CoreRouter.decode($0, as: ToolApprovalDecisionRequest.self) }
            guard let record = await service.approveToolApproval(
                id: approvalId,
                decidedBy: payload?.decidedBy,
                scope: payload?.scope ?? .once
            ) else {
                return CoreRouter.json(status: HTTPStatus.notFound, payload: ["error": "not_found"])
            }
            return CoreRouter.encodable(status: HTTPStatus.ok, payload: record)
        }

        router.post("/v1/tool-approvals/:approvalId/reject", metadata: RouteMetadata(summary: "Reject tool call", description: "Rejects a pending risky tool call", tags: ["Tools"])) { request in
            let approvalId = request.pathParam("approvalId") ?? ""
            let payload = request.body.flatMap { CoreRouter.decode($0, as: ToolApprovalDecisionRequest.self) }
            guard let record = await service.rejectToolApproval(id: approvalId, decidedBy: payload?.decidedBy) else {
                return CoreRouter.json(status: HTTPStatus.notFound, payload: ["error": "not_found"])
            }
            return CoreRouter.encodable(status: HTTPStatus.ok, payload: record)
        }

        router.get("/v1/channel-approvals/pending", metadata: RouteMetadata(summary: "List pending approvals", description: "Returns all pending channel access approval requests", tags: ["Channels"])) { request in
            let platform = request.queryParam("platform")
            let pending: [PendingApprovalEntry]
            if let platform {
                pending = await service.listPendingApprovals(platform: platform)
            } else {
                pending = await service.listPendingApprovals()
            }
            return CoreRouter.encodable(status: HTTPStatus.ok, payload: pending)
        }

        router.get("/v1/channel-approvals/users", metadata: RouteMetadata(summary: "List access users", description: "Returns approved and blocked channel access users", tags: ["Channels"])) { request in
            let platform = request.queryParam("platform")
            let users = await service.listAccessUsers(platform: platform)
            return CoreRouter.encodable(status: HTTPStatus.ok, payload: users)
        }

        router.post("/v1/channel-approvals/:approvalId/approve", metadata: RouteMetadata(summary: "Approve pending request", description: "Approves a pending channel access request with verification code", tags: ["Channels"])) { request in
            let approvalId = request.pathParam("approvalId") ?? ""
            guard let body = request.body,
                  let payload = CoreRouter.decode(body, as: ChannelApprovalCodeRequest.self)
            else {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidBody])
            }
            let ok = await service.approvePendingApproval(id: approvalId, code: payload.code)
            if ok {
                return CoreRouter.json(status: HTTPStatus.ok, payload: ["ok": "true"])
            }
            return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": "invalid_code_or_not_found"])
        }

        router.post("/v1/channel-approvals/:approvalId/reject", metadata: RouteMetadata(summary: "Reject pending request", description: "Rejects and removes a pending channel access request", tags: ["Channels"])) { request in
            let approvalId = request.pathParam("approvalId") ?? ""
            await service.rejectPendingApproval(id: approvalId)
            return CoreRouter.json(status: HTTPStatus.ok, payload: ["ok": "true"])
        }

        router.post("/v1/channel-approvals/:approvalId/block", metadata: RouteMetadata(summary: "Block pending request", description: "Blocks a user from a pending channel access request", tags: ["Channels"])) { request in
            let approvalId = request.pathParam("approvalId") ?? ""
            let ok = await service.blockPendingApproval(id: approvalId)
            if ok {
                return CoreRouter.json(status: HTTPStatus.ok, payload: ["ok": "true"])
            }
            return CoreRouter.json(status: HTTPStatus.notFound, payload: ["error": "not_found"])
        }

        router.delete("/v1/channel-approvals/users/:userId", metadata: RouteMetadata(summary: "Delete access user", description: "Removes an approved or blocked user from the channel access list", tags: ["Channels"])) { request in
            let userId = request.pathParam("userId") ?? ""
            let ok = await service.deleteAccessUser(id: userId)
            if ok {
                return CoreRouter.json(status: HTTPStatus.ok, payload: ["ok": "true"])
            }
            return CoreRouter.json(status: HTTPStatus.notFound, payload: ["error": "not_found"])
        }
    }
}
