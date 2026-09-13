export const PICKUP_FIELDS = [
  { id: "author", label: "Author", hint: "Logins or stable user IDs, e.g. alice, bob" },
  { id: "assignee", label: "Assignee", hint: "Tracker logins/IDs, or local actor IDs" },
  { id: "queue", label: "Tracker queue", hint: "Queue keys, e.g. CORE, MOBILE" },
  { id: "issue_type", label: "Tracker issue type", hint: "Type keys, e.g. bug, task" },
  { id: "priority", label: "Priority", hint: "high, medium, low, or a Tracker priority key" },
  { id: "external_status", label: "Tracker status", hint: "Status keys, e.g. open, inProgress" },
  { id: "tag", label: "Tag", hint: "Tag values, e.g. ios, manual" },
  { id: "title", label: "Title", hint: "Title text" },
  { id: "description", label: "Description", hint: "Description text" },
  { id: "source", label: "Source", hint: "startrek, github, or local" },
  { id: "kind", label: "Local task kind", hint: "planning, execution, bugfix" }
];

export const PICKUP_OPERATORS = [
  { id: "one_of", label: "is one of" },
  { id: "not_one_of", label: "is not one of" },
  { id: "contains", label: "contains text" },
  { id: "is_set", label: "is present" },
  { id: "is_not_set", label: "is missing" }
];

export function clonePickupRules(rules) {
  return {
    matchMode: rules?.matchMode || "all",
    conditions: Array.isArray(rules?.conditions) ? rules.conditions.map((condition) => ({
      ...condition,
      values: Array.isArray(condition.values) ? [...condition.values] : []
    })) : []
  };
}

export function pickupRulesError(rules) {
  if (!["all", "any"].includes(rules.matchMode)) return "Choose how conditions are combined.";
  if (rules.conditions.length > 50) return "Use at most 50 conditions.";
  for (const [index, condition] of rules.conditions.entries()) {
    if (!PICKUP_FIELDS.some((field) => field.id === condition.field) ||
        !PICKUP_OPERATORS.some((operator) => operator.id === condition.operation)) {
      return `Condition ${index + 1} is unsupported. Remove it or choose a supported field and operator.`;
    }
    if (condition.operation === "contains" && !["title", "description"].includes(condition.field)) {
      return `Condition ${index + 1}: text matching is available for title and description.`;
    }
    if (!["is_set", "is_not_set"].includes(condition.operation) && !condition.values.some((value) => String(value).trim())) {
      return `Add a value to condition ${index + 1}.`;
    }
  }
  return "";
}

export function pickupIdentityOptions(tasks, field) {
  if (!["author", "assignee"].includes(field)) return [];
  const options = new Map();
  for (const task of tasks) {
    const metadata = task.externalMetadata;
    const identity = field === "author" ? metadata?.externalCreator : metadata?.externalAssigneeIdentity;
    const value = String(metadata?.providerId
      ? identity?.login || identity?.id || ""
      : (field === "author" ? task.createdBy : task.actorId) || "").trim();
    if (!value) continue;
    const display = identity?.displayName;
    options.set(value.toLowerCase(), { id: value, label: display && display !== value ? `${display} (${value})` : value });
  }
  return [...options.values()].sort((left, right) => left.label.localeCompare(right.label));
}
