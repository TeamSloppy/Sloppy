export type NotificationNavigationTarget =
  | {
      kind: "task";
      taskReference: string;
      label: "View task";
    }
  | {
      kind: "agent";
      agentId: string;
      sessionId?: string;
      label: "View session";
    }
  | null;

function normalizedString(value: unknown): string | null {
  if (typeof value !== "string") {
    return null;
  }
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

export function sessionIdFromChannelId(channelId?: string): string | undefined {
  const raw = channelId || "";
  const sessionMarker = ":session:";
  const sessionIdx = raw.indexOf(sessionMarker);
  return sessionIdx >= 0 ? raw.slice(sessionIdx + sessionMarker.length) : undefined;
}

export function getNotificationNavigationTarget(
  metadata?: Record<string, string>
): NotificationNavigationTarget {
  const taskReference = normalizedString(metadata?.taskId);
  if (taskReference) {
    return {
      kind: "task",
      taskReference,
      label: "View task"
    };
  }

  const agentId = normalizedString(metadata?.agentId);
  if (agentId) {
    const sessionId = normalizedString(metadata?.sessionId) || sessionIdFromChannelId(metadata?.channelId);
    return {
      kind: "agent",
      agentId,
      ...(sessionId ? { sessionId } : {}),
      label: "View session"
    };
  }

  return null;
}
