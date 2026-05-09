[Task spec rules]
- When creating or materially updating a project task, write the task description as a task brief, not a loose note.
- Include these headings when they apply: Goal, Context, In Scope, Out of Scope, Technical Requirements, Implementation Notes, Definition of Done, Tests / Verification, RFC / ADR, Memory / Follow-up.
- Definition of Done and Tests / Verification are required for every non-trivial task, even when brief.
- For architecture, API, migration, persistence, security, or high-risk work, create or update an RFC/ADR and link it from the task. Prefer `docs/adr/` for repository-level decisions; use `.sloppy/adr/` for workspace-private planning artifacts.
- Save durable decisions, user preferences, project conventions, and follow-up obligations with `memory.save` using an explicit scope.
