import assert from "node:assert/strict";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import path from "node:path";
import { chromium } from "playwright";
const root = fileURLToPath(new URL("../", import.meta.url));
const harness = await mkdtemp(path.join(root, ".team-roles-test-"));
const port = 25128;
const server = spawn(process.execPath, ["node_modules/vite/bin/vite.js", "--host", "127.0.0.1", "--port", String(port), "--strictPort"], { cwd: root, stdio: "pipe" });
let browser;
try {
  await writeFile(path.join(harness, "index.html"), '<html><div id="root"></div><script type="module" src="./main.jsx"></script></html>');
  await writeFile(path.join(harness, "main.jsx"), `import React, { useState } from "react";
import { createRoot } from "react-dom/client";
import { TeamBoardPanel } from "../src/views/Projects/TeamBoardPanel";
import { ProjectTasksTab } from "../src/views/Projects/ProjectTasksTab";
import { TaskDetailView } from "../src/views/Projects/ProjectTaskDetails";
import { normalizeTask } from "../src/views/Projects/utils";
import { TaskStageAssignmentsEditor } from "../src/views/Projects/TaskStageAssignmentsEditor";
import "../src/styles/index.css";
const actors = [{id:"agent:anton",displayName:"Антон",systemRole:"developer"},{id:"agent:yadev",displayName:"Yadev"}];
const initialTeams = [{id:"team:best",name:"Best Team",memberActorIds:actors.map(a=>a.id),memberRoles:{"agent:anton":["developer"],"agent:yadev":["reviewer","qa"]}}];
function App() {
 const [teams,setTeams] = useState(initialTeams), [project,setProject] = useState({id:"test",teams:[]});
 const [draft,setDraft] = useState({teamId:"team:best",stageAssignments:null});
 return <main style={{maxWidth:960,margin:"24px auto",padding:16}}><h2>Team responsibilities</h2>
 <TeamBoardPanel project={project} actors={actors} teams={teams} onTeamsChange={setTeams} onUpdateProject={async patch=>{window.savedProject=patch;setProject({...project,...patch});return {...project,...patch};}} />
 <TaskStageAssignmentsEditor draft={draft} actors={actors} teams={teams} onChange={value=>{window.savedAssignments=value;setDraft({...draft,stageAssignments:value});}} /></main>;
}
const appRoot = createRoot(document.getElementById("root"));
appRoot.render(<App/>);
window.showTaskDetails = () => {
 const task = normalizeTask({id:"SLP-41",title:"QR code sign-in",status:"backlog",teamId:"team:best",stageAssignments:{developer:"agent:anton",reviewer:"agent:yadev",qa:"agent:yadev"}});
 function Details() {
  const [draft,setDraft]=useState({...task});
  return <TaskDetailView project={{id:"test",name:"Sloppy",tasks:[task],channels:[]}} task={task} editDraft={draft}
   createModalActors={actors} createModalTeams={initialTeams} agentDirectory={{}}
   updateEditDraft={(field,value)=>setDraft({...draft,[field]:value})} saveTaskEdit={()=>{window.savedDetail=draft;}} revertTaskEdit={()=>setDraft({...task})}
   closeTaskDetails={()=>{}} updateDetailAssignee={()=>{}} deleteTaskFromModal={()=>{}} openTaskDetails={()=>{}} />;
 }
 appRoot.render(<Details/>);
};
window.showKanban = () => {
 const tasks = [normalizeTask({id:"SLP-41",title:"QR code sign-in",status:"needs_review",teamId:"team:best",stageAssignments:{developer:"agent:anton",reviewer:"agent:yadev",qa:"agent:yadev"}})];
 appRoot.render(<main style={{padding:24}}><ProjectTasksTab project={{id:"test",name:"Sloppy",teams:["team:best"],tasks}} createModalActors={actors} createModalTeams={initialTeams} onUpdateProject={async ()=>null} onTeamsChange={()=>{}} /></main>);
};`);
  for (let attempt = 0; ; attempt++) {
    try { if ((await fetch(`http://127.0.0.1:${port}`)).ok) break; } catch {}
    if (attempt === 100) throw new Error("Vite did not start");
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  browser = await chromium.launch({ headless: true, ...(process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE ? { executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE } : {}) });
  const page = await browser.newPage({ viewport: { width: 1100, height: 950 } });
  const errors = [];
  page.on("pageerror", (error) => errors.push(error.message));
  let savedTeam, fail = false;
  await page.route("**/v1/actors/teams/**", async (route) => {
    savedTeam = route.request().postDataJSON();
    await route.fulfill({ status: fail ? 500 : 200, contentType: "application/json", body: JSON.stringify(fail ? {} : { teams: [savedTeam] }) });
  });
  await page.goto(`http://127.0.0.1:${port}/${path.basename(harness)}/`);
  await page.getByRole("button", { name: "Board team", exact: true }).click();
  await page.getByRole("button", { name: "Best Team", exact: true }).click();
  assert.deepEqual(await page.evaluate(() => window.savedProject), { teams: ["team:best"] });
  await page.getByRole("button", { name: "Members & roles" }).click();
  await page.getByRole("checkbox", { name: "Антон: Reviewer", exact: true }).check();
  await page.getByRole("button", { name: "Save roles", exact: true }).click();
  await page.getByRole("button", { name: "Cancel", exact: true }).waitFor({ state: "hidden" });
  assert.deepEqual(savedTeam.memberRoles["agent:anton"], ["developer", "reviewer"]);
  assert.deepEqual(savedTeam.memberRoles["agent:yadev"], ["reviewer", "qa"]);
  await page.getByRole("button", { name: "Use team defaults" }).click();
  assert.deepEqual(await page.evaluate(() => window.savedAssignments), { developer: "agent:anton", reviewer: "agent:anton", qa: "agent:yadev" });
  await page.getByText(/Self-review ·/).waitFor();
  await page.getByRole("button", { name: "Reviewer assignee", exact: true }).click();
  await page.locator(".team-assignment-menu").getByRole("button", { name: "Yadev", exact: true }).click();
  assert.equal(await page.evaluate(() => window.savedAssignments.reviewer), "agent:yadev");
  await page.getByText("The reviewer also owns QA.").waitFor();
  await page.screenshot({ path: "/tmp/sloppy-team-desktop.png", fullPage: true });
  fail = true;
  await page.getByRole("button", { name: "Members & roles" }).click();
  await page.getByRole("button", { name: "Save roles", exact: true }).click();
  await page.getByRole("alert").waitFor();
  await page.getByRole("button", { name: "Cancel", exact: true }).click();
  await page.setViewportSize({ width: 375, height: 900 });
  await page.getByRole("button", { name: "QA assignee", exact: true }).click();
  assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth));
  await page.keyboard.press("Escape");
  await page.screenshot({ path: "/tmp/sloppy-team-mobile.png", fullPage: true });
  await page.route("**/v1/agents", (route) => route.fulfill({contentType:"application/json",body:"[]"}));
  await page.setViewportSize({ width: 1500, height: 1000 });
  await page.evaluate(() => window.showKanban());
  await page.getByRole("heading", { name: "QR code sign-in" }).waitFor();
  await page.getByText("Developer: Антон · Reviewer: Yadev · QA: Yadev", { exact: true }).waitFor();
  await page.getByRole("heading", { name: "QR code sign-in" }).scrollIntoViewIfNeeded();
  await page.screenshot({ path: "/tmp/sloppy-team-kanban.png", fullPage: true });
  await page.route("**/v1/**", (route) => route.fulfill({contentType:"application/json",body:"{}"}));
  await page.evaluate(() => window.showTaskDetails());
  await page.getByRole("button", { name: "Reviewer assignee", exact: true }).click();
  await page.locator(".team-assignment-menu").getByRole("button", { name: "Антон", exact: true }).click();
  await page.locator(".settings-toast--visible").waitFor();
  await page.getByRole("button", { name: "Apply", exact: true }).click();
  assert.equal(await page.evaluate(() => window.savedDetail.stageAssignments.reviewer), "agent:anton");
  await page.screenshot({ path: "/tmp/sloppy-team-task-details.png", fullPage: true });
  assert.deepEqual(errors, []);
  console.log("Team roles browser checks passed: board linking, multi-role save, defaults, self-review, QA/review overlap, failed save, keyboard and mobile layout.");
} finally {
  await browser?.close(); server.kill(); await rm(harness, { recursive: true, force: true });
}
