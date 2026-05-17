export type TutorialRouteSection = "projects" | "actors";

export interface TutorialStep {
  id: string;
  title: string;
  body: string;
  emptyProjectBody?: string;
  route: {
    section: TutorialRouteSection;
    projectTab?: string;
  };
  targetId?: string;
  beforeEnter?: string;
}

export const PROJECT_TUTORIAL_STORAGE_KEY = "sloppy_dashboard_project_tutorial_v1";

export const tutorialSteps: TutorialStep[] = [
  {
    id: "welcome",
    title: "Welcome",
    body: "Projects are where Sloppy understands a real workspace. This quick tour shows how repo context, tasks, actors, automation, review, and GitHub sync fit together.",
    emptyProjectBody: "Projects are where Sloppy understands a real workspace. Start by creating or opening a project; the rest of the tour will explain the workspace pieces you will see there.",
    route: { section: "projects" }
  },
  {
    id: "projects-overview",
    title: "Projects overview",
    body: "Create or open projects here. The local repo/path matters because Sloppy uses it as the source of code context, working tree state, automation scope, and task history.",
    route: { section: "projects" },
    targetId: "projects-overview"
  },
  {
    id: "task-board",
    title: "Task board",
    body: "The task board organizes work by status. Columns show the lifecycle from backlog through ready, in progress, review states, done, and blockers.",
    emptyProjectBody: "Task boards live inside a project. Create or open a project first, then return here to see status columns and task cards.",
    route: { section: "projects", projectTab: "tasks" },
    targetId: "project-task-board"
  },
  {
    id: "create-tasks",
    title: "Create tasks",
    body: "Create Task opens a guided form for title, description, priority, kind, assignee or team, and the task loop mode override.",
    emptyProjectBody: "Create Task appears after you open a project. Use it to describe work, priority, kind, assignee/team, and loop mode.",
    route: { section: "projects", projectTab: "tasks" },
    targetId: "create-task-button"
  },
  {
    id: "move-tasks",
    title: "Move tasks",
    body: "Drag and drop task cards between columns to change status. Open a task detail panel when you need richer edits, comments, review, or assignment changes.",
    emptyProjectBody: "After you create a project, its task board supports drag/drop status moves and task detail edits.",
    route: { section: "projects", projectTab: "tasks" },
    targetId: "project-task-board"
  },
  {
    id: "task-loop-mode",
    title: "Human vs Agent in the loop",
    body: "Task Loop Mode controls the default execution policy. Human in the Loop keeps human review/approval central; Agent in the Loop lets agents advance work more autonomously.",
    emptyProjectBody: "Task Loop Mode is configured per project. Create or open a project, then visit Settings to choose Human in the Loop or Agent in the Loop.",
    route: { section: "projects", projectTab: "settings" },
    targetId: "task-loop-mode"
  },
  {
    id: "autonomous-execution",
    title: "Autonomous execution",
    body: "VISOR automation can pick tasks sequentially or in parallel. Autonomous work still depends on review expectations and an available worktree for safe execution.",
    emptyProjectBody: "VISOR automation is project-scoped. Once a project exists, Settings explains automation, review expectations, and worktree requirements.",
    route: { section: "projects", projectTab: "settings" },
    targetId: "autonomous-execution"
  },
  {
    id: "github-sync",
    title: "GitHub Projects sync",
    body: "Task Sync connects Sloppy tasks with GitHub issues and Projects. Use Discover, Link/Save, Sync Now, status mappings, and token override when you need repository-specific auth.",
    emptyProjectBody: "GitHub sync settings appear inside project Settings. Create or open a project to connect issues, Projects, status mappings, and token override.",
    route: { section: "projects", projectTab: "settings" },
    targetId: "task-sync-settings"
  },
  {
    id: "actors-board",
    title: "Actors board",
    body: "Actors can be humans or agents. The board exposes actions, links, teams, and routing patterns for peer-style collaboration or hierarchical delegation.",
    route: { section: "actors" },
    targetId: "actors-board-actions"
  }
];
