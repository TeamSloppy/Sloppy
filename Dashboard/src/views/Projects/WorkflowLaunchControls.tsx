import React, { useState } from "react";
import { WorkflowChoice } from "./WorkflowChoice";

type RecordValue = Record<string, any>;
export function WorkflowLaunchControls({ project, workflow, selectedTask, busy, onLaunch }: {
  project: RecordValue; workflow: RecordValue; selectedTask?: RecordValue | null; busy: boolean; onLaunch: (payload: RecordValue) => void;
}) {
  const [taskId, setTaskId] = useState(String(selectedTask?.id || ""));
  const defaults = workflow.nodes?.find((node: RecordValue) => node.type === "trigger")?.config?.executionEnvironment || {};
  const [mode, setMode] = useState(defaults.mode || "project");
  const [path, setPath] = useState(defaults.path || "");
  const [baseRef, setBaseRef] = useState(defaults.baseRef || "HEAD");
  const [setupCommand, setSetupCommand] = useState(defaults.setupCommand || "");
  const [inputText, setInputText] = useState("{}");
  let input: RecordValue = {};
  let error = "";
  try {
    input = JSON.parse(inputText);
    if (!input || Array.isArray(input) || typeof input !== "object") error = "Input must be a JSON object.";
  } catch { error = "Input must be valid JSON."; }
  const tasks = [...(project.tasks || []).filter((task: RecordValue) => !task.isArchived)];
  if (selectedTask?.id && !tasks.some((task: RecordValue) => task.id === selectedTask.id)) tasks.push(selectedTask);
  const requiresTask = mode === "task_worktree" || workflow.nodes?.some((node: RecordValue) => node.type === "project_task" || node.config?.requiresTask === true);
  if (requiresTask && !taskId) error = "Choose a task for this workflow.";
  if (mode === "existing_worktree" && !path.trim()) error = "Provide the worktree directory.";
  return <form className="project-workflow-launch" onSubmit={(event) => {
    event.preventDefault();
    if (!error) onLaunch({ taskId: taskId || null, input, environment: {
      mode, path: mode === "existing_worktree" ? path.trim() : undefined,
      baseRef: mode === "new_worktree" ? baseRef.trim() : undefined,
      setupCommand: setupCommand.trim() || undefined
    } });
  }}>
    <h3>Run workflow</h3>
    <WorkflowChoice label="Task" value={taskId} options={[{ value: "", label: "No task" }, ...tasks.map((task: RecordValue) => ({ value: task.id, label: task.title }))]} onChange={setTaskId} />
    <WorkflowChoice label="Execution environment" value={mode} onChange={setMode} options={[
      { value: "project", label: "Project workspace" }, { value: "task_worktree", label: "Task worktree" },
      { value: "existing_worktree", label: "Existing worktree" }, { value: "new_worktree", label: "New worktree" }
    ]} />
    {mode === "existing_worktree" ? <label>Worktree directory<input value={path} onChange={(event) => setPath(event.target.value)} placeholder="/absolute/path/to/worktree" /></label> : null}
    {mode === "new_worktree" ? <label>Base revision<input value={baseRef} onChange={(event) => setBaseRef(event.target.value)} placeholder="HEAD, origin/HEAD, branch, tag or commit" /><small>The revision is resolved and pinned when the run is created.</small></label> : null}
    <label>Setup command (optional)<textarea rows={3} value={setupCommand} onChange={(event) => setSetupCommand(event.target.value)} /><small>Runs once in the selected directory. Interrupted setup requires reconciliation.</small></label>
    <label>Workflow input JSON<textarea rows={5} value={inputText} onChange={(event) => setInputText(event.target.value)} /></label>
    <small>The selected task is snapshotted into task fields. Task, environment and input survive approvals and server restarts.</small>
    {error ? <p role="alert">{error}</p> : null}
    <button type="submit" disabled={busy || Boolean(error)}>Start workflow</button>
  </form>;
}
