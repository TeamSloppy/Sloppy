export const FILTER_FIELDS = [
  { id: "tag", label: "Tag" },
  { id: "assignee", label: "Assignee", hint: "Assigned or currently working participant" },
  { id: "team", label: "Team" },
  { id: "status", label: "Status" },
  { id: "priority", label: "Priority" },
  { id: "author", label: "Author" },
  { id: "source", label: "Source" },
  { id: "external_assignee", label: "Tracker assignee" },
  { id: "queue", label: "Tracker queue" },
  { id: "external_status", label: "Tracker status" },
  { id: "issue_type", label: "Tracker issue type" },
  { id: "kind", label: "Task kind" },
  { id: "developer", label: "Developer" },
  { id: "reviewer", label: "Reviewer" },
  { id: "qa", label: "QA owner" },
  { id: "title", label: "Title", text: true },
  { id: "description", label: "Description", text: true }
];
export const FILTER_OPERATORS = [
  { id: "is", label: "is any of" },
  { id: "is_not", label: "is none of" },
  { id: "contains", label: "contains" },
  { id: "not_contains", label: "does not contain" },
  { id: "is_empty", label: "is empty" },
  { id: "is_not_empty", label: "is not empty" }
];
const clean = (value) => typeof value === "string" ? value.trim() : "";
const fold = (value) => clean(value).normalize("NFKC").toLowerCase();
const values = (items) => [...new Set(items.map(clean).filter(Boolean))];
export const emptyTaskFilter = () => ({ query: "", match: "all", rules: [] });
export const newFilterRule = () => ({ id: globalThis.crypto?.randomUUID?.() || `${Date.now()}-${Math.random()}`, field: "tag", operation: "is", values: [] });
export function normalizeTaskFilter(filter) {
  return {
    query: typeof filter?.query === "string" ? filter.query : "",
    match: filter?.match || "all",
    rules: Array.isArray(filter?.rules) ? filter.rules.map((rule, index) => ({
      id: clean(rule?.id) || `rule-${index}`,
      field: clean(rule?.field), operation: clean(rule?.operation),
      values: Array.isArray(rule?.values) ? values(rule.values) : []
    })) : []
  };
}
export function filterError(filter) {
  if (!["all", "any"].includes(filter.match)) return "Choose All or Any conditions.";
  for (const [index, rule] of filter.rules.entries()) {
    if (!FILTER_FIELDS.some((field) => field.id === rule.field) || !FILTER_OPERATORS.some((item) => item.id === rule.operation)) {
      return `Condition ${index + 1} is unsupported. Edit or remove it.`;
    }
    if (!["is_empty", "is_not_empty"].includes(rule.operation) && !rule.values.some(clean)) return `Choose a value for condition ${index + 1}.`;
  }
  return "";
}
export function taskFieldValues(task, field) {
  const metadata = task.externalMetadata || {};
  switch (field) {
    case "tag": return values(Array.isArray(task.tags) ? task.tags : []);
    case "assignee": return values([task.actorId, task.claimedActorId, task.claimedAgentId ? `agent:${task.claimedAgentId}` : ""]);
    case "team": return values([task.teamId]);
    case "author": return metadata.providerId
      ? values([metadata.externalCreator?.login, metadata.externalCreator?.id]) : values([task.createdBy]);
    case "source": return [clean(metadata.providerId) || "local"];
    case "external_assignee": return values([metadata.externalAssigneeIdentity?.login, metadata.externalAssigneeIdentity?.id, metadata.externalAssignee]);
    case "queue": return values([metadata.externalQueue]);
    case "external_status": return values([metadata.externalStatus?.key]);
    case "issue_type": return values([metadata.externalIssueType]);
    case "developer": case "reviewer": case "qa": return values([task.stageAssignments?.[field]]);
    default: return values([task[field]]);
  }
}
export function taskMatchesFilter(task, filter) {
  if (filterError(filter)) return false;
  const query = fold(filter.query);
  if (query) {
    const ids = values([task.id, task.externalMetadata?.externalIssueKey]);
    const haystack = fold([...ids, ...ids.map((id) => `#${id}`), task.title, task.description].filter(Boolean).join(" "));
    if (!query.split(/\s+/).every((word) => haystack.includes(word))) return false;
  }
  if (!filter.rules.length) return true;
  const matches = filter.rules.map((rule) => {
    const actual = taskFieldValues(task, rule.field).map(fold);
    const expected = rule.values.map(fold).filter(Boolean);
    switch (rule.operation) {
      case "is": return actual.some((value) => expected.includes(value));
      case "is_not": return !actual.some((value) => expected.includes(value));
      case "contains": return actual.some((value) => expected.some((item) => value.includes(item)));
      case "not_contains": return !actual.some((value) => expected.some((item) => value.includes(item)));
      case "is_empty": return actual.length === 0;
      case "is_not_empty": return actual.length > 0;
      default: return false;
    }
  });
  return filter.match === "any" ? matches.some(Boolean) : matches.every(Boolean);
}
export function filterValueOptions(field, tasks, actors = [], teams = []) {
  const options = new Map();
  const add = (id, label = id) => { if (clean(id)) options.set(fold(id), { id: clean(id), label: clean(label) || clean(id) }); };
  const constants = {
    status: [["backlog", "Backlog"], ["ready", "Ready to work"], ["in_progress", "In progress"], ["waiting_input", "Waiting input"], ["blocked", "Blocked"], ["needs_review", "Needs review"], ["done", "Done"]],
    priority: [["high", "High"], ["medium", "Medium"], ["low", "Low"]],
    source: [["local", "Local"], ["startrek", "Tracker"], ["github", "GitHub"]],
    kind: [["planning", "Planning"], ["execution", "Execution"], ["bugfix", "Bugfix"]]
  };
  tasks.forEach((task) => taskFieldValues(task, field).forEach((value) => add(value)));
  (constants[field] || []).forEach(([id, label]) => add(id, label));
  if (["assignee", "developer", "reviewer", "qa"].includes(field)) actors.forEach((actor) => add(actor.id, actor.displayName || actor.id));
  if (field === "team") teams.forEach((team) => add(team.id, team.name));
  if (["author", "external_assignee"].includes(field)) tasks.forEach((task) => {
    const identity = field === "author" ? task.externalMetadata?.externalCreator : task.externalMetadata?.externalAssigneeIdentity;
    for (const id of values([identity?.login, identity?.id])) add(id, identity?.displayName ? `${identity.displayName} (${id})` : id);
  });
  return [...options.values()].sort((a, b) => a.label.localeCompare(b.label));
}
export const hasTaskFilter = (filter) => Boolean(clean(filter.query) || filter.rules.length);
export const filtersEqual = (a, b) => JSON.stringify(normalizeTaskFilter(a)) === JSON.stringify(normalizeTaskFilter(b));
export const taskFilterStorageKey = (server, projectId) => `sloppy.kanban.filters.v1:${encodeURIComponent(server.replace(/\/+$/, ""))}:${encodeURIComponent(projectId)}`;
export const emptyFilterState = () => ({ version: 1, filter: emptyTaskFilter(), saved: [], activeId: "" });
export function parseFilterState(raw) {
  if (!raw) return emptyFilterState();
  const value = JSON.parse(raw);
  if (value?.version !== 1 || !Array.isArray(value.saved) || !value.filter || !Array.isArray(value.filter.rules)) throw new Error("Unsupported filter data");
  const saved = value.saved.map((entry) => {
    if (!clean(entry?.id) || !clean(entry?.name) || !entry.filter || !Array.isArray(entry.filter.rules)) throw new Error("Invalid saved filter");
    return { id: entry.id, name: entry.name, filter: normalizeTaskFilter(entry.filter) };
  });
  return { version: 1, filter: normalizeTaskFilter(value.filter), saved, activeId: saved.some((entry) => entry.id === value.activeId) ? value.activeId : "" };
}
