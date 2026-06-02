export function resolveProjectLiveUpdatesId(routeProjectId, selectedProject) {
  const selectedProjectId = String(selectedProject?.id || "").trim();
  if (selectedProjectId) {
    return selectedProjectId;
  }
  return String(routeProjectId || "").trim();
}

export function projectNotificationTargetsLiveUpdates(notification, projectId) {
  const normalizedProjectId = String(projectId || "").trim();
  if (!normalizedProjectId) {
    return false;
  }

  const metadata = notification?.metadata && typeof notification.metadata === "object"
    ? notification.metadata
    : {};
  const notificationProjectId = String(metadata.projectId || "").trim();
  const notificationTaskId = String(metadata.taskId || "").trim();
  if (notificationProjectId !== normalizedProjectId || !notificationTaskId) {
    return false;
  }

  return ["task_completed", "input_required", "agent_error"].includes(String(notification?.type || ""));
}
