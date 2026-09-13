# Saved kanban filters

The project's Tasks tab supports named board filters. Use **Filters** to add
conditions, choose **All conditions** (AND) or **Any condition** (OR), and apply.
Multiple values in one condition are alternatives. Search matches all entered
words against the title, description, local task ID and external issue key;
references such as `#CORE-42` are supported.

Conditions cover tags, assigned/current participants, teams, status, priority,
authors, source, Tracker metadata, task kind, and Developer/Reviewer/QA owners.
Operators support inclusion, exclusion, literal text matching and missing values.
Matching ignores case. Missing fields match exclusions and explicit empty checks.
Author and external-assignee values use stable IDs/logins, with names shown as
labels; source metadata is never guessed from descriptions or tags.

**Save as…** creates a named filter. An edited saved filter offers **Save changes…**;
**Rename…** changes its name, and the delete button removes that saved definition.
Deleting the selected definition restores all tasks. Duplicate names are rejected.
The chosen filter, including unsaved adjustments, survives reload. Filters are
stored in this browser's localStorage, separately for each API server and project;
they are not shared with teammates or synchronized between devices. Storage
failures are displayed instead of silently claiming persistence.

Board counts, swarm summaries and archived lists respect the filter. Hidden tasks
are removed from bulk selection; bulk actions intersect their IDs with the current
visible tasks before dispatch. Filters change visibility only, not task state,
synchronization, worker pickup or Autopilot rules.

Validation: `node --test tests/taskFilters.test.js` from Dashboard, plus typecheck,
production build, and browser checks against the actual ProjectTasksTab component.
