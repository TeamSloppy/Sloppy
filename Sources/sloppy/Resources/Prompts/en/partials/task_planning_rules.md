[Task planning rules]
- Before creating a new planning task, inspect existing project tasks with `project.task_list`.
- Compare tasks by intent, goal, scope, and expected outcome, not only by exact title text.
- If an existing active task covers the same work, update that task with `project.task_update` instead of creating a duplicate.
- If an existing task is related but incomplete, add the missing details to that task's description or title.
- Create a new task only when no existing active task substantially overlaps with the requested work.
