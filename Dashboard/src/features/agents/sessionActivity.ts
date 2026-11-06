export function isTerminalRunStage(stage) {
  const value = String(stage || "").trim().toLowerCase();
  return value === "done" || value === "interrupted";
}

export function extractEventKey(event, index) {
  return event?.id || `${event?.type || "event"}-${index}`;
}

type PendingToolCall = { eventKey: string; recordId: string; toolName: string };

export function findPendingToolCallRecordIds(events: unknown): Set<string> {
  const openCallsByTool = new Map<string, PendingToolCall[]>();
  const openCallsById = new Map<string, PendingToolCall>();
  const pendingRecordIds = new Set<string>();

  for (let index = 0; index < (Array.isArray(events) ? events.length : 0); index += 1) {
    const eventItem = events[index];
    if (eventItem?.importOrigin != null || eventItem?.forkOrigin != null) {
      continue;
    }

    if (eventItem?.type === "run_status" && isTerminalRunStage(eventItem.runStatus?.stage)) {
      openCallsByTool.clear();
      openCallsById.clear();
      pendingRecordIds.clear();
      continue;
    }

    if (eventItem?.type === "tool_call" && eventItem.toolCall) {
      const toolName = String(eventItem.toolCall.tool || "").trim();
      const eventKey = String(extractEventKey(eventItem, index));
      const recordId = `${eventKey}-tool-call`;
      const call = { eventKey, recordId, toolName };
      pendingRecordIds.add(recordId);
      if (!openCallsByTool.has(toolName)) {
        openCallsByTool.set(toolName, []);
      }
      openCallsByTool.get(toolName).push(call);
      openCallsById.set(eventKey, call);
      continue;
    }

    if (eventItem?.type === "tool_result" && eventItem.toolResult) {
      const toolName = String(eventItem.toolResult.tool || "").trim();
      const queue = openCallsByTool.get(toolName) || [];
      const callEventId = String(eventItem.toolResult.callEventId || eventItem.runtimeMetadata?.callEventId || "").trim();
      let matched: PendingToolCall | undefined;
      if (callEventId) {
        matched = openCallsById.get(callEventId);
        if (!matched || matched.toolName !== toolName) {
          continue;
        }
        const position = queue.indexOf(matched);
        if (position < 0) {
          continue;
        }
        queue.splice(position, 1);
      } else {
        matched = queue.shift();
      }
      if (queue.length === 0) {
        openCallsByTool.delete(toolName);
      } else {
        openCallsByTool.set(toolName, queue);
      }
      if (matched) {
        pendingRecordIds.delete(matched.recordId);
        openCallsById.delete(matched.eventKey);
      }
    }
  }

  return pendingRecordIds;
}
