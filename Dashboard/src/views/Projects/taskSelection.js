function normalizeTaskId(value) {
  return String(value || "").trim();
}

export function compareProjectKanbanTasks(left, right) {
  if (left.swarmId && right.swarmId && left.swarmId !== right.swarmId) {
    return left.swarmId.localeCompare(right.swarmId);
  }
  if (left.swarmId && !right.swarmId) {
    return -1;
  }
  if (!left.swarmId && right.swarmId) {
    return 1;
  }
  if ((left.swarmDepth ?? 0) !== (right.swarmDepth ?? 0)) {
    return (left.swarmDepth ?? 0) - (right.swarmDepth ?? 0);
  }
  return new Date(left.createdAt).getTime() - new Date(right.createdAt).getTime();
}

export function sortProjectKanbanColumnTasks(tasks) {
  return [...tasks].sort(compareProjectKanbanTasks);
}

export function buildProjectTaskSelectionOrder(tasks, statuses) {
  const taskList = Array.isArray(tasks) ? tasks : [];
  const statusList = Array.isArray(statuses) ? statuses : [];
  return statusList.flatMap((status) => {
    const statusId = normalizeTaskId(status?.id);
    if (!statusId) {
      return [];
    }
    return sortProjectKanbanColumnTasks(taskList.filter((task) => task.status === statusId))
      .map((task) => normalizeTaskId(task.id))
      .filter(Boolean);
  });
}

export function taskSelectionRangeIds(orderedTaskIds, anchorTaskId, targetTaskId) {
  const normalizedIds = (Array.isArray(orderedTaskIds) ? orderedTaskIds : [])
    .map(normalizeTaskId)
    .filter(Boolean);
  const normalizedAnchor = normalizeTaskId(anchorTaskId);
  const normalizedTarget = normalizeTaskId(targetTaskId);
  const targetIndex = normalizedIds.indexOf(normalizedTarget);
  if (!normalizedTarget || targetIndex < 0) {
    return [];
  }

  const anchorIndex = normalizedIds.indexOf(normalizedAnchor);
  if (anchorIndex < 0) {
    return [normalizedTarget];
  }

  const start = Math.min(anchorIndex, targetIndex);
  const end = Math.max(anchorIndex, targetIndex);
  return normalizedIds.slice(start, end + 1);
}
