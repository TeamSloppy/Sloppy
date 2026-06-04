function taskId(value) {
  return String(value || "").trim();
}

function uniqueTasks(tasks) {
  const seen = new Set();
  const result = [];
  for (const task of tasks) {
    const id = taskId(task?.id);
    if (!id || seen.has(id)) {
      continue;
    }
    seen.add(id);
    result.push(task);
  }
  return result;
}

function byId(tasks) {
  const map = new Map();
  for (const task of tasks) {
    const id = taskId(task?.id);
    if (id) {
      map.set(id, task);
    }
  }
  return map;
}

export function buildRelatedIssueGroups(task, tasks) {
  const currentId = taskId(task?.id);
  const taskList = Array.isArray(tasks) ? tasks : [];
  const taskMap = byId(taskList);
  const parentId = taskId(task?.parentTaskId);
  const dependencyIds = Array.isArray(task?.dependsOnTaskIds)
    ? task.dependsOnTaskIds.map(taskId).filter(Boolean)
    : [];
  const groups = [];

  const parent = parentId ? taskMap.get(parentId) : null;
  if (parent) {
    groups.push({
      id: "parent",
      title: "Parent",
      items: [{ task: parent, relation: "Parent" }]
    });
  }

  const children = uniqueTasks(taskList.filter((candidate) => taskId(candidate?.parentTaskId) === currentId));
  if (children.length > 0) {
    groups.push({
      id: "children",
      title: "Child issues",
      items: children.map((child) => ({ task: child, relation: "Child" }))
    });
  }

  const blocks = uniqueTasks(taskList.filter((candidate) => {
    const ids = Array.isArray(candidate?.dependsOnTaskIds) ? candidate.dependsOnTaskIds : [];
    return ids.map(taskId).includes(currentId);
  }));
  if (blocks.length > 0) {
    groups.push({
      id: "blocks",
      title: "Blocks",
      items: blocks.map((blockedTask) => ({ task: blockedTask, relation: "Blocks" }))
    });
  }

  const blockedBy = uniqueTasks(dependencyIds.map((id) => taskMap.get(id)).filter(Boolean));
  if (blockedBy.length > 0) {
    groups.push({
      id: "blocked_by",
      title: "Blocked by",
      items: blockedBy.map((dependency) => ({ task: dependency, relation: "Blocked by" }))
    });
  }

  const swarmId = taskId(task?.swarmId);
  const swarmTaskId = taskId(task?.swarmTaskId) || (currentId ? `task:${currentId}` : "");
  const linkedIds = new Set(groups.flatMap((group) => group.items.map((item) => taskId(item.task?.id))));
  const swarmChildren = uniqueTasks(taskList.filter((candidate) => (
    taskId(candidate?.id) !== currentId &&
    taskId(candidate?.swarmId) === swarmId &&
    taskId(candidate?.swarmParentTaskId) === swarmTaskId &&
    !linkedIds.has(taskId(candidate?.id))
  )));
  if (swarmId && swarmChildren.length > 0) {
    groups.push({
      id: "swarm_children",
      title: "Swarm children",
      items: swarmChildren.map((child) => ({ task: child, relation: "Swarm child" }))
    });
  }

  return groups;
}
